#pragma once

#include <QColor>
#include <QFileSystemWatcher>
#include <QObject>
#include <QPalette>
#include <QProcess>
#include <QTimer>

// Watches the active Omarchy theme (`colors.toml`) and Hyprland corner
// rounding, exposing Libadwaita-aligned semantic color and radius tokens to
// QML and syncing a matching QPalette for Qt / Kirigami controls.
class Theme : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool isDark READ isDark NOTIFY changed)
    Q_PROPERTY(QString accent READ accent NOTIFY changed)
    Q_PROPERTY(QString accentForeground READ accentForeground NOTIFY changed)
    Q_PROPERTY(QColor accentText READ accentText NOTIFY changed)
    Q_PROPERTY(QColor windowBg READ windowBg NOTIFY changed)
    Q_PROPERTY(QColor headerBg READ headerBg NOTIFY changed)
    Q_PROPERTY(QColor cardBg READ cardBg NOTIFY changed)
    Q_PROPERTY(QColor cardHoverBg READ cardHoverBg NOTIFY changed)
    Q_PROPERTY(QColor cardSelectedBg READ cardSelectedBg NOTIFY changed)
    Q_PROPERTY(QColor popoverBg READ popoverBg NOTIFY changed)
    Q_PROPERTY(QColor border READ border NOTIFY changed)
    Q_PROPERTY(QColor borderStrong READ borderStrong NOTIFY changed)
    Q_PROPERTY(QColor fg READ fg NOTIFY changed)
    Q_PROPERTY(QColor fgMuted READ fgMuted NOTIFY changed)
    Q_PROPERTY(QColor positive READ positive NOTIFY changed)
    Q_PROPERTY(QColor warning READ warning NOTIFY changed)
    Q_PROPERTY(QColor negative READ negative NOTIFY changed)
    Q_PROPERTY(int radius READ radius NOTIFY changed)
    Q_PROPERTY(int cardRadius READ cardRadius NOTIFY changed)
    Q_PROPERTY(int controlRadius READ controlRadius NOTIFY changed)
    Q_PROPERTY(int pillRadius READ pillRadius NOTIFY changed)

public:
    explicit Theme(const QString &currentDirectory = {}, QObject *parent = nullptr, const QString &hyprctl = {});
    ~Theme() override;

    bool isDark() const { return m_isDark; }
    QString accent() const { return m_accent; }
    QString accentForeground() const;
    QColor accentText() const { return m_accentText; }
    QColor windowBg() const { return m_windowBg; }
    QColor headerBg() const { return m_headerBg; }
    QColor cardBg() const { return m_cardBg; }
    QColor cardHoverBg() const { return m_cardHoverBg; }
    QColor cardSelectedBg() const { return m_cardSelectedBg; }
    QColor popoverBg() const { return m_popoverBg; }
    QColor border() const { return m_border; }
    QColor borderStrong() const { return m_borderStrong; }
    QColor fg() const { return m_fg; }
    QColor fgMuted() const { return m_fgMuted; }
    QColor positive() const { return m_positive; }
    QColor warning() const { return m_warning; }
    QColor negative() const { return m_negative; }
    int radius() const { return m_radius; }
    int cardRadius() const { return m_radius == 0 ? 0 : qBound(10, m_radius * 2, 12); }
    int controlRadius() const { return m_radius == 0 ? 0 : qBound(6, m_radius, 8); }
    int pillRadius() const { return m_radius == 0 ? 0 : 999; }

    // Adjusts a feed status color so pill text stays legible in both dark and
    // light themes while preserving its hue.
    Q_INVOKABLE QColor statusColor(const QString &hex) const;

    // Builds a QPalette matching the current theme for native Qt & Kirigami widgets.
    QPalette palette() const;

    static QString readAccent(const QString &path);

signals:
    void changed();

private:
    void reload();
    void refreshRounding();

    QString m_directory;
    bool m_isDark = true;
    QString m_accent = "#FFD60A";
    QColor m_accentText;
    QColor m_windowBg;
    QColor m_headerBg;
    QColor m_cardBg;
    QColor m_cardHoverBg;
    QColor m_cardSelectedBg;
    QColor m_popoverBg;
    QColor m_border;
    QColor m_borderStrong;
    QColor m_fg;
    QColor m_fgMuted;
    QColor m_positive;
    QColor m_warning;
    QColor m_negative;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QString m_hyprctl;
    int m_radius = 0;
    QProcess m_roundingProcess;
    QTimer m_roundingPoll, m_roundingTimeout;
};
