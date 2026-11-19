#pragma once

#include <QByteArray>
#include <QDateTime>
#include <QHash>
#include <QObject>
#include <QString>

// [streamlock-patch] v11
//
// Two-tier local stream password for Moonlight PC:
//   * an administrator password protects the configuration (setting, changing
//     or removing per-PC passwords, and deleting a PC)
//   * every PC can have its own stream password, asked before streaming
//
// Passwords are stored as salted, iterated SHA-256 hashes in QSettings.
class StreamLock : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool adminPasswordSet READ adminPasswordSet NOTIFY stateChanged)
    Q_PROPERTY(bool adminUnlocked READ adminUnlocked NOTIFY stateChanged)
    Q_PROPERTY(int revision READ revision NOTIFY stateChanged)
    Q_PROPERTY(int minimumPasswordLength READ minimumPasswordLength CONSTANT)
    Q_PROPERTY(int unlockWindowMinutes READ unlockWindowMinutes NOTIFY stateChanged)

public:
    explicit StreamLock(QObject* parent = nullptr);

    bool adminPasswordSet() const;
    bool adminUnlocked() const;
    int revision() const { return m_revision; }
    int minimumPasswordLength() const { return kMinimumPasswordLength; }

    // --- Administrator password ---
    // Returns an empty string on success, otherwise a user-visible error.
    Q_INVOKABLE QString setAdminPassword(const QString& currentPassword, const QString& newPassword);
    Q_INVOKABLE QString verifyAdminPassword(const QString& password);
    Q_INVOKABLE QString removeAdminPassword(const QString& password);
    Q_INVOKABLE void lockAdmin();

    // --- Per-host stream passwords ---
    Q_INVOKABLE bool hostHasPassword(const QString& hostUuid) const;
    Q_INVOKABLE bool hostUnlocked(const QString& hostUuid) const;
    Q_INVOKABLE QString unlockHost(const QString& hostUuid, const QString& password);
    // Accepts either the admin password or the PC's current stream password.
    // On success the caller may change/remove the password of that PC.
    Q_INVOKABLE QString authorizeHostEdit(const QString& hostUuid, const QString& password);
    Q_INVOKABLE QString setHostPassword(const QString& hostUuid, const QString& password);
    Q_INVOKABLE QString removeHostPassword(const QString& hostUuid);
    Q_INVOKABLE void lockHost(const QString& hostUuid);
    Q_INVOKABLE void lockAllHosts();

    // Seconds left in the "too many failed attempts" cooldown (0 = not blocked).
    Q_INVOKABLE int cooldownRemaining() const;

    int unlockWindowMinutes() const;
    Q_INVOKABLE void setUnlockWindowMinutes(int minutes);

signals:
    void stateChanged();

private:
    bool checkCooldown(QString& error);
    bool checkStored(const QString& prefix, const QString& password) const;
    bool verifyStored(const QString& prefix, const QString& password);
    bool hostEditAuthorized(const QString& hostUuid) const;
    void resetFailures();
    void storePassword(const QString& prefix, const QString& password);
    void eraseStored(const QString& prefix);
    bool hasStored(const QString& prefix) const;
    void registerFailure();
    void notifyChanged();

    static QString hostPrefix(const QString& hostUuid) { return QStringLiteral("hosts/") + hostUuid; }

    static constexpr int kMinimumPasswordLength = 4;

    int m_revision = 0;
    int m_failCount = 0;
    QDateTime m_lockoutUntil;
    QDateTime m_adminUnlockedUntil;
    QHash<QString, QDateTime> m_hostUnlockedUntil;
    QHash<QString, QDateTime> m_hostEditUntil;
};
