#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QTimer>
#include <QVariantMap>

// Mission Control's view of FlightDeck. It reads the daemon's state.json and
// re-reads it whenever the daemon replaces it; every change goes through the
// `flightdeck` CLI, so the daemon stays the only writer of state.
class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString problem READ problem NOTIFY stateChanged)
    Q_PROPERTY(QString message READ message NOTIFY messageChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    // `dataDirectory` and `program` default to ~/.local/share/flightdeck and
    // the `flightdeck` on PATH; tests pass a temp dir and a fake script.
    explicit Backend(const QString &dataDirectory = {}, const QString &program = {}, QObject *parent = nullptr);

    QVariantMap state() const { return m_state; }
    // Why there is no state to show, or empty when there is.
    QString problem() const { return m_problem; }
    // The outcome of the last action, for the status line.
    QString message() const { return m_message; }
    bool busy() const { return m_running > 0; }

    // `value` is "on", "off" or "auto" (follow the live feed).
    Q_INVOKABLE void setMilestone(int id, const QString &value);
    Q_INVOKABLE void pin(int id);
    Q_INVOKABLE void unpin();
    Q_INVOKABLE void sync();
    Q_INVOKABLE void copyChecklist();
    Q_INVOKABLE void copyWeekend();

signals:
    void stateChanged();
    void messageChanged();
    void toastRequested(const QString &message);
    void busyChanged();

private:
    void reload();
    void rewatch();
    void run(const QStringList &args, const QString &done);
    void setMessage(const QString &message);

    QString m_directory;
    QString m_program;
    QVariantMap m_state;
    QString m_problem;
    QString m_message;
    int m_running = 0;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
};
