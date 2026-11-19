// [streamlock-patch] v11
#include "streamlock.h"

#include <QCryptographicHash>
#include <QRandomGenerator>
#include <QSettings>

namespace {
constexpr const char* kGroup = "streamlock";
constexpr const char* kAdminPrefix = "admin";
constexpr const char* kHostsPrefix = "hosts";
constexpr const char* kUnlockWindow = "unlockwindow";

constexpr int kDefaultIterations = 120000;
constexpr int kDefaultUnlockWindow = 30; // minutes
constexpr int kMaxUnlockWindow = 1440;   // minutes
constexpr int kAdminUnlockWindow = 10;   // minutes
constexpr int kCooldownThreshold = 3;    // failed attempts before a cooldown
constexpr int kSaltSize = 16;

QByteArray deriveHash(const QString& password, const QByteArray& salt, int iterations)
{
    QByteArray digest = salt + password.toUtf8();
    digest = QCryptographicHash::hash(digest, QCryptographicHash::Sha256);
    for (int i = 1; i < iterations; i++) {
        digest = QCryptographicHash::hash(salt + digest, QCryptographicHash::Sha256);
    }
    return digest;
}

bool constantTimeEquals(const QByteArray& a, const QByteArray& b)
{
    if (a.size() != b.size()) {
        return false;
    }

    unsigned char diff = 0;
    for (int i = 0; i < a.size(); i++) {
        diff |= static_cast<unsigned char>(a.at(i) ^ b.at(i));
    }
    return diff == 0;
}
} // namespace

StreamLock::StreamLock(QObject* parent)
    : QObject(parent)
{
}

void StreamLock::notifyChanged()
{
    m_revision++;
    emit stateChanged();
}

int StreamLock::cooldownRemaining() const
{
    if (!m_lockoutUntil.isValid()) {
        return 0;
    }

    const qint64 secs = QDateTime::currentDateTime().secsTo(m_lockoutUntil);
    return secs > 0 ? static_cast<int>(secs) : 0;
}

int StreamLock::unlockWindowMinutes() const
{
    QSettings settings;
    settings.beginGroup(kGroup);
    return qBound(1, settings.value(kUnlockWindow, kDefaultUnlockWindow).toInt(), kMaxUnlockWindow);
}

void StreamLock::setUnlockWindowMinutes(int minutes)
{
    QSettings settings;
    settings.beginGroup(kGroup);
    settings.setValue(kUnlockWindow, qBound(1, minutes, kMaxUnlockWindow));
    settings.sync();
    notifyChanged();
}

bool StreamLock::checkCooldown(QString& error)
{
    const int wait = cooldownRemaining();
    if (wait > 0) {
        error = tr("尝试次数过多，请 %1 秒后再试。").arg(wait);
        return false;
    }

    return true;
}

bool StreamLock::hasStored(const QString& prefix) const
{
    QSettings settings;
    settings.beginGroup(kGroup);
    return !settings.value(prefix + "/hash").toString().isEmpty();
}

void StreamLock::storePassword(const QString& prefix, const QString& password)
{
    QByteArray salt(kSaltSize, '\0');
    for (int i = 0; i < salt.size(); i++) {
        salt[i] = static_cast<char>(QRandomGenerator::global()->bounded(256));
    }

    QSettings settings;
    settings.beginGroup(kGroup);
    settings.setValue(prefix + "/salt", QString::fromLatin1(salt.toHex()));
    settings.setValue(prefix + "/hash", QString::fromLatin1(deriveHash(password, salt, kDefaultIterations).toHex()));
    settings.setValue(prefix + "/iterations", kDefaultIterations);
    settings.sync();
}

void StreamLock::eraseStored(const QString& prefix)
{
    QSettings settings;
    settings.beginGroup(kGroup);
    settings.remove(prefix);
    settings.sync();
}

void StreamLock::registerFailure()
{
    m_failCount++;
    if (m_failCount >= kCooldownThreshold) {
        const int shift = qMin(m_failCount - kCooldownThreshold, 5);
        m_lockoutUntil = QDateTime::currentDateTime().addSecs(qMin(300, 10 << shift));
    }
    notifyChanged();
}

bool StreamLock::checkStored(const QString& prefix, const QString& password) const
{
    QSettings settings;
    settings.beginGroup(kGroup);

    const QByteArray salt = QByteArray::fromHex(settings.value(prefix + "/salt").toString().toLatin1());
    const QByteArray stored = QByteArray::fromHex(settings.value(prefix + "/hash").toString().toLatin1());
    int iterations = settings.value(prefix + "/iterations", kDefaultIterations).toInt();
    if (iterations <= 0) {
        iterations = kDefaultIterations;
    }

    // Nothing configured for this entry - nothing to verify
    if (salt.isEmpty() || stored.isEmpty()) {
        return true;
    }

    return constantTimeEquals(deriveHash(password, salt, iterations), stored);
}

void StreamLock::resetFailures()
{
    m_failCount = 0;
    m_lockoutUntil = QDateTime();
}

bool StreamLock::verifyStored(const QString& prefix, const QString& password)
{
    if (checkStored(prefix, password)) {
        resetFailures();
        return true;
    }

    registerFailure();
    return false;
}

// ---------------------------------------------------------------- admin

bool StreamLock::adminPasswordSet() const
{
    return hasStored(kAdminPrefix);
}

bool StreamLock::adminUnlocked() const
{
    return adminPasswordSet() && m_adminUnlockedUntil.isValid() &&
            QDateTime::currentDateTime() < m_adminUnlockedUntil;
}

QString StreamLock::setAdminPassword(const QString& currentPassword, const QString& newPassword)
{
    if (newPassword.length() < kMinimumPasswordLength) {
        return tr("密码长度至少需要 %1 位。").arg(kMinimumPasswordLength);
    }

    QString error;
    if (!checkCooldown(error)) {
        return error;
    }

    if (adminPasswordSet() && !verifyStored(kAdminPrefix, currentPassword)) {
        return tr("当前管理员密码不正确。");
    }

    storePassword(kAdminPrefix, newPassword);

    m_failCount = 0;
    m_lockoutUntil = QDateTime();
    m_adminUnlockedUntil = QDateTime::currentDateTime().addSecs(kAdminUnlockWindow * 60);
    notifyChanged();
    return QString();
}

QString StreamLock::verifyAdminPassword(const QString& password)
{
    if (!adminPasswordSet()) {
        return tr("还没有设置管理员密码。");
    }

    QString error;
    if (!checkCooldown(error)) {
        return error;
    }

    if (!verifyStored(kAdminPrefix, password)) {
        return tr("管理员密码不正确。");
    }

    m_adminUnlockedUntil = QDateTime::currentDateTime().addSecs(kAdminUnlockWindow * 60);
    notifyChanged();
    return QString();
}

QString StreamLock::removeAdminPassword(const QString& password)
{
    if (!adminPasswordSet()) {
        return QString();
    }

    QString error;
    if (!checkCooldown(error)) {
        return error;
    }

    if (!verifyStored(kAdminPrefix, password)) {
        return tr("当前管理员密码不正确。");
    }

    // Host passwords become unmanageable without an administrator password
    eraseStored(kAdminPrefix);
    eraseStored(kHostsPrefix);

    m_hostUnlockedUntil.clear();
    m_hostEditUntil.clear();
    m_adminUnlockedUntil = QDateTime();
    notifyChanged();
    return QString();
}

void StreamLock::lockAdmin()
{
    m_adminUnlockedUntil = QDateTime();
    notifyChanged();
}

// ---------------------------------------------------------------- hosts

bool StreamLock::hostHasPassword(const QString& hostUuid) const
{
    if (hostUuid.isEmpty()) {
        return false;
    }

    return hasStored(hostPrefix(hostUuid));
}

bool StreamLock::hostUnlocked(const QString& hostUuid) const
{
    if (!hostHasPassword(hostUuid)) {
        return false;
    }

    return m_hostUnlockedUntil.contains(hostUuid) &&
            m_hostUnlockedUntil.value(hostUuid) > QDateTime::currentDateTime();
}

QString StreamLock::unlockHost(const QString& hostUuid, const QString& password)
{
    if (hostUuid.isEmpty() || !hostHasPassword(hostUuid)) {
        return QString();
    }

    QString error;
    if (!checkCooldown(error)) {
        return error;
    }

    if (!verifyStored(hostPrefix(hostUuid), password)) {
        return tr("密码不正确。");
    }

    m_hostUnlockedUntil[hostUuid] = QDateTime::currentDateTime().addSecs(unlockWindowMinutes() * 60);
    notifyChanged();
    return QString();
}

bool StreamLock::hostEditAuthorized(const QString& hostUuid) const
{
    if (adminUnlocked()) {
        return true;
    }

    return m_hostEditUntil.contains(hostUuid) &&
            m_hostEditUntil.value(hostUuid) > QDateTime::currentDateTime();
}

QString StreamLock::authorizeHostEdit(const QString& hostUuid, const QString& password)
{
    if (hostUuid.isEmpty()) {
        return tr("找不到这台电脑。");
    }

    QString error;
    if (!checkCooldown(error)) {
        return error;
    }

    const bool adminOk = adminPasswordSet() && checkStored(kAdminPrefix, password);
    const bool hostOk = hostHasPassword(hostUuid) && checkStored(hostPrefix(hostUuid), password);

    if (adminOk) {
        m_adminUnlockedUntil = QDateTime::currentDateTime().addSecs(kAdminUnlockWindow * 60);
        resetFailures();
        notifyChanged();
        return QString();
    }

    if (hostOk) {
        m_hostEditUntil[hostUuid] = QDateTime::currentDateTime().addSecs(kAdminUnlockWindow * 60);
        resetFailures();
        notifyChanged();
        return QString();
    }

    registerFailure();
    return tr("密码不正确。");
}

QString StreamLock::setHostPassword(const QString& hostUuid, const QString& password)
{
    if (!hostEditAuthorized(hostUuid)) {
        return tr("请先输入管理员密码或这台电脑的串流密码。");
    }

    if (hostUuid.isEmpty()) {
        return tr("找不到这台电脑。");
    }

    if (password.length() < kMinimumPasswordLength) {
        return tr("密码长度至少需要 %1 位。").arg(kMinimumPasswordLength);
    }

    storePassword(hostPrefix(hostUuid), password);

    // Force a new prompt before the next stream
    m_hostUnlockedUntil.remove(hostUuid);
    notifyChanged();
    return QString();
}

QString StreamLock::removeHostPassword(const QString& hostUuid)
{
    if (!hostEditAuthorized(hostUuid)) {
        return tr("请先输入管理员密码或这台电脑的串流密码。");
    }

    if (hostUuid.isEmpty()) {
        return tr("找不到这台电脑。");
    }

    eraseStored(hostPrefix(hostUuid));
    m_hostUnlockedUntil.remove(hostUuid);
    notifyChanged();
    return QString();
}

void StreamLock::lockHost(const QString& hostUuid)
{
    m_hostUnlockedUntil.remove(hostUuid);
    notifyChanged();
}

void StreamLock::lockAllHosts()
{
    m_hostUnlockedUntil.clear();
    notifyChanged();
}
