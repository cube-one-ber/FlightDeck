#include "backend.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QStandardPaths>

// The state.json shape this build understands; see the daemon's state.rs.
static constexpr int SchemaVersion = 1;

Backend::Backend(const QString &dataDirectory, const QString &program, QObject *parent)
    : QObject(parent),
      m_directory(!dataDirectory.isEmpty() ? dataDirectory
                  : !qEnvironmentVariableIsEmpty("XDG_DATA_HOME") ? qEnvironmentVariable("XDG_DATA_HOME") + "/flightdeck"
                  : QDir::homePath() + "/.local/share/flightdeck"),
      // `flightdeck open` passes itself in FLIGHTDECK_CLI; otherwise use the one on PATH.
      m_program(!program.isEmpty() ? program
                : !qEnvironmentVariableIsEmpty("FLIGHTDECK_CLI") ? qEnvironmentVariable("FLIGHTDECK_CLI")
                : QStandardPaths::findExecutable("flightdeck")) {
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(50);
    connect(&m_debounce, &QTimer::timeout, this, &Backend::reload);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { m_debounce.start(); });
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] { m_debounce.start(); });
    reload();
}

// The daemon replaces state.json by rename, which drops a watch on the file
// itself, so watch the directory as well and re-arm after every change.
void Backend::rewatch() {
    const auto paths = m_watcher.files() + m_watcher.directories();
    if (!paths.isEmpty())
        m_watcher.removePaths(paths);
    QString dir = m_directory;
    while (!QFileInfo::exists(dir) && dir != "/")
        dir = QFileInfo(dir).absolutePath();
    m_watcher.addPath(dir);
    if (QFileInfo::exists(m_directory + "/state.json"))
        m_watcher.addPath(m_directory + "/state.json");
}

void Backend::reload() {
    rewatch();
    QString problem;
    QVariantMap state;
    QFile file(m_directory + "/state.json");
    if (!file.open(QIODevice::ReadOnly)) {
        problem = tr("No data yet. Start the service with: systemctl --user enable --now flightdeck");
    } else {
        QJsonParseError error;
        const auto doc = QJsonDocument::fromJson(file.readAll(), &error);
        if (error.error != QJsonParseError::NoError)
            problem = tr("state.json could not be read: %1").arg(error.errorString());
        else if (doc.object().value("schema_version").toInt() != SchemaVersion)
            problem = tr("state.json is from a different FlightDeck version. Update the app and the service together.");
        else
            state = doc.object().toVariantMap();
    }
    // Keep showing the last good state if a read fails half-way.
    if (state.isEmpty() && !m_state.isEmpty() && file.exists())
        return;
    if (state != m_state || problem != m_problem) {
        m_state = state;
        m_problem = problem;
        emit stateChanged();
    }
}

void Backend::setMessage(const QString &message) {
    if (message != m_message) {
        m_message = message;
        emit messageChanged();
    }
    if (!message.isEmpty())
        emit toastRequested(message);
}

void Backend::run(const QStringList &args, const QString &done) {
    if (m_program.isEmpty()) {
        setMessage(tr("The flightdeck command is not installed."));
        return;
    }
    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::SeparateChannels);
    ++m_running;
    emit busyChanged();
    connect(process, &QProcess::finished, this, [this, process, done](int code, QProcess::ExitStatus status) {
        const QString err = QString::fromUtf8(process->readAllStandardError()).trimmed();
        if (code == 0 && status == QProcess::NormalExit)
            setMessage(done);
        else
            setMessage(err.isEmpty() ? tr("flightdeck failed (exit %1)").arg(code) : err.section('\n', 0, 0));
        process->deleteLater();
        --m_running;
        emit busyChanged();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        setMessage(tr("Could not run %1").arg(m_program));
        process->deleteLater();
        --m_running;
        emit busyChanged();
    });
    process->start(m_program, args);
}

void Backend::setMilestone(int id, const QString &value) {
    run({"milestone", QString::number(id), value}, value == "auto" ? tr("Following the live feed") : tr("Override saved"));
}

void Backend::pin(int id) { run({"pin", QString::number(id)}, tr("Pinned to the bar")); }
void Backend::unpin() { run({"pin", "--clear"}, tr("Pin cleared")); }
// With the daemon running, `sync` only asks it to fetch, so don't claim it finished.
void Backend::sync() { run({"sync"}, tr("Sync requested")); }
void Backend::copyChecklist() { run({"checklist", "--copy"}, tr("Checklist copied")); }
void Backend::copyWeekend() { run({"weekend", "--copy"}, tr("Weekend slate copied")); }
