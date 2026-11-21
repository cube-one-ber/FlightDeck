#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

#include "backend.h"
#include "theme.h"

class FlightDeckTests : public QObject {
    Q_OBJECT

private slots:
    void reportsMissingState()
    {
        QTemporaryDir dir;
        Backend backend(dir.path(), "/bin/true");
        QVERIFY(backend.state().isEmpty());
        QVERIFY(backend.problem().contains("systemctl --user"));
    }

    void followsAtomicReplacement()
    {
        QTemporaryDir dir;
        write(dir.filePath("state.json"), R"({"schema_version":1,"bar":{"label":"F9"}})");
        Backend backend(dir.path(), "/bin/true");
        QCOMPARE(backend.state().value("bar").toMap().value("label").toString(), QString("F9"));

        // The daemon writes beside the file and renames over it.
        write(dir.filePath(".state.json.tmp"), R"({"schema_version":1,"bar":{"label":"FH"}})");
        QVERIFY(QFile::remove(dir.filePath("state.json")));
        QVERIFY(QFile::rename(dir.filePath(".state.json.tmp"), dir.filePath("state.json")));
        QTRY_COMPARE(backend.state().value("bar").toMap().value("label").toString(), QString("FH"));

        // And again, to prove the watch was re-armed.
        write(dir.filePath(".state.json.tmp"), R"({"schema_version":1,"bar":{"label":"SS"}})");
        QVERIFY(QFile::remove(dir.filePath("state.json")));
        QVERIFY(QFile::rename(dir.filePath(".state.json.tmp"), dir.filePath("state.json")));
        QTRY_COMPARE(backend.state().value("bar").toMap().value("label").toString(), QString("SS"));
    }

    void rejectsOtherSchemaVersions()
    {
        QTemporaryDir dir;
        write(dir.filePath("state.json"), R"({"schema_version":2})");
        Backend backend(dir.path(), "/bin/true");
        QVERIFY(backend.state().isEmpty());
        QVERIFY(backend.problem().contains("different FlightDeck version"));
    }

    void actionsGoThroughTheCli()
    {
        QTemporaryDir dir;
        const QString log = dir.filePath("args"), cli = dir.filePath("flightdeck");
        write(cli, "#!/bin/sh\necho \"$@\" >> '" + log.toUtf8() + "'\n[ \"$1\" = sync ] && { echo 'network down' >&2; exit 1; }\nexit 0\n");
        QVERIFY(QFile::setPermissions(cli, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));

        Backend backend(dir.path(), cli);
        backend.setMilestone(41, "on");
        QTRY_VERIFY(!backend.busy());
        QCOMPARE(backend.message(), QString("Override saved"));
        backend.pin(8335);
        QTRY_VERIFY(!backend.busy());
        backend.sync();
        QTRY_VERIFY(!backend.busy());
        QCOMPARE(backend.message(), QString("network down"));

        QFile f(log);
        QVERIFY(f.open(QIODevice::ReadOnly));
        QCOMPARE(QString::fromUtf8(f.readAll()), QString("milestone 41 on\npin 8335\nsync\n"));
    }

    void themeFallsBack()
    {
        QTemporaryDir dir;
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#FFD60A"));
        QVERIFY(theme.isDark());
        QCOMPARE(theme.cardRadius(), 0);
    }

    void themeReadsLightAndDarkPalettes()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("theme");
        write(dir.filePath("theme/colors.toml"),
              "mode = \"light\"\naccent = \"#3584e4\"\nbackground = \"#ffffff\"\ndark_background = \"#f2f2f4\"\nforeground = \"#1e1e1e\"\n");
        Theme theme(dir.path());
        QVERIFY(!theme.isDark());
        QCOMPARE(theme.accent(), QString("#3584e4"));
        QCOMPARE(theme.cardBg(), QColor("#ffffff"));
        // Light theme must darken pale status colors so pills stay legible.
        QVERIFY(theme.statusColor("#7ED47E").lightnessF() < QColor("#7ED47E").lightnessF());
    }

    void repeatedMessagesStillTriggerToasts()
    {
        QTemporaryDir dir;
        const QString cli = dir.filePath("flightdeck");
        write(cli, "#!/bin/sh\nexit 0\n");
        QVERIFY(QFile::setPermissions(cli, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));

        Backend backend(dir.path(), cli);
        QSignalSpy toasts(&backend, &Backend::toastRequested);
        backend.copyChecklist();
        QTRY_COMPARE(toasts.count(), 1);
        backend.copyChecklist();
        QTRY_COMPARE(toasts.count(), 2);
    }

private:
    static void write(const QString &path, const QByteArray &contents)
    {
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(contents);
    }
};

QTEST_MAIN(FlightDeckTests)
#include "flightdeck_tests.moc"
