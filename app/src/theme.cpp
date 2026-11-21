// Theme watching follows Omacut (MIT, David Heinemeier Hansson).
#include "theme.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStandardPaths>
#include <algorithm>
#include <cmath>

namespace {

double relativeLuminance(const QColor &c) {
    auto linear = [](double v) { return v <= .04045 ? v / 12.92 : std::pow((v + .055) / 1.055, 2.4); };
    return .2126 * linear(c.redF()) + .7152 * linear(c.greenF()) + .0722 * linear(c.blueF());
}

double contrastRatio(const QColor &a, const QColor &b) {
    const double l1 = relativeLuminance(a);
    const double l2 = relativeLuminance(b);
    return (std::max(l1, l2) + 0.05) / (std::min(l1, l2) + 0.05);
}

QColor mixColors(const QColor &a, const QColor &b, double t) {
    t = std::clamp(t, 0.0, 1.0);
    return QColor::fromRgbF(
        a.redF() + (b.redF() - a.redF()) * t,
        a.greenF() + (b.greenF() - a.greenF()) * t,
        a.blueF() + (b.blueF() - a.blueF()) * t,
        1.0);
}

QColor withAlpha(const QColor &c, double alpha) {
    QColor out(c);
    out.setAlphaF(std::clamp(alpha, 0.0, 1.0));
    return out;
}

// Nudges `color` toward white/dark until it reaches `minContrast` against
// either raw `bg` or a tinted pill surface (`mix(bg, color, pillAlpha)`).
QColor ensureContrast(const QColor &color, const QColor &bg, bool isDark,
                      double minContrast = 4.5, double pillAlpha = 0.0) {
    if (!color.isValid())
        return isDark ? QColor("#f2f2f4") : QColor("#1e1e1e");
    auto surfaceFor = [&](const QColor &c) {
        return pillAlpha > 0.0 ? mixColors(bg, c, pillAlpha) : bg;
    };
    if (contrastRatio(color, surfaceFor(color)) >= minContrast)
        return color;
    // Lift warm dark-mode accents toward warm cream instead of cold white so
    // terracotta/coral hues stay true to their palette instead of turning pink.
    const bool warmHue = isDark && color.hslHue() >= 0 && color.hslHue() <= 55 && color.hslSaturationF() > 0.25;
    const QColor target = isDark ? (warmHue ? QColor("#fff0dc") : QColor("#ffffff")) : QColor("#101012");
    QColor adjusted = color;
    for (int i = 1; i <= 24; ++i) {
        adjusted = mixColors(color, target, i / 24.0);
        if (contrastRatio(adjusted, surfaceFor(adjusted)) >= minContrast)
            break;
    }
    return adjusted;
}

struct ParsedTheme {
    QString mode;
    QHash<QString, QString> colors;
};

ParsedTheme parseColorsToml(const QString &path) {
    ParsedTheme parsed;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return parsed;
    const QString text = QString::fromUtf8(file.readAll());

    static const QRegularExpression modeRe(R"re(^\s*mode\s*=\s*["']([^"']+)["'])re",
                                           QRegularExpression::MultilineOption);
    const auto modeMatch = modeRe.match(text);
    if (modeMatch.hasMatch())
        parsed.mode = modeMatch.captured(1).trimmed().toLower();

    static const QRegularExpression colorRe(R"re(^\s*([a-zA-Z0-9_]+)\s*=\s*["'](#[0-9a-fA-F]{6})["'])re",
                                            QRegularExpression::MultilineOption);
    auto it = colorRe.globalMatch(text);
    while (it.hasNext()) {
        const auto m = it.next();
        parsed.colors.insert(m.captured(1), m.captured(2));
    }
    return parsed;
}

} // namespace

Theme::Theme(const QString &directory, QObject *parent, const QString &hyprctl)
    : QObject(parent),
      m_directory(directory.isEmpty() ? QDir::homePath() + "/.local/state/omarchy/current" : directory) {
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(80);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { m_debounce.start(); });
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] { m_debounce.start(); });
    connect(&m_debounce, &QTimer::timeout, this, &Theme::reload);

    // Corners follow Hyprland's effective rounding, which themes and personal
    // overrides can both set, so ask hyprctl rather than reading its config.
    // Without Hyprland the corners stay sharp, like Omarchy's default.
    m_hyprctl = !hyprctl.isEmpty() ? hyprctl
              : directory.isEmpty() && !qEnvironmentVariableIsEmpty("HYPRLAND_INSTANCE_SIGNATURE")
                  ? QStandardPaths::findExecutable("hyprctl") : QString();
    m_roundingTimeout.setSingleShot(true);
    m_roundingTimeout.setInterval(500);
    connect(&m_roundingTimeout, &QTimer::timeout, &m_roundingProcess, &QProcess::kill);
    connect(&m_roundingProcess, &QProcess::errorOccurred, this, [this] { m_roundingTimeout.stop(); });
    connect(&m_roundingProcess, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        m_roundingTimeout.stop();
        const auto value = QJsonDocument::fromJson(m_roundingProcess.readAllStandardOutput()).object().value("int");
        if (code != 0 || status != QProcess::NormalExit || !value.isDouble() || value.toInt(-1) < 0)
            return;
        if (value.toInt() != m_radius) {
            m_radius = value.toInt();
            emit changed();
        }
    });
    m_roundingPoll.setInterval(1000);
    connect(&m_roundingPoll, &QTimer::timeout, this, &Theme::refreshRounding);
    if (!m_hyprctl.isEmpty())
        m_roundingPoll.start();
    reload();
}

Theme::~Theme() {
    if (m_roundingProcess.state() != QProcess::NotRunning) {
        m_roundingProcess.kill();
        m_roundingProcess.waitForFinished(1000);
    }
}

void Theme::refreshRounding() {
    if (m_hyprctl.isEmpty() || m_roundingProcess.state() != QProcess::NotRunning)
        return;
    m_roundingProcess.start(m_hyprctl, {"-j", "getoption", "decoration:rounding"});
    m_roundingTimeout.start();
}

QString Theme::readAccent(const QString &path) {
    const auto parsed = parseColorsToml(path);
    return parsed.colors.value("accent", "#FFD60A");
}

// White reads best on saturated blues and warm mid-tones (GNOME/Apple HIG),
// while bright yellows and pale pastels switch to dark ink.
QString Theme::accentForeground() const {
    return relativeLuminance(QColor(m_accent)) > .36 ? "black" : "white";
}

QColor Theme::statusColor(const QString &hex) const {
    QColor base(hex);
    if (!base.isValid())
        return m_fgMuted;
    return ensureContrast(base, m_cardBg, m_isDark, m_isDark ? 5.5 : 5.2, m_isDark ? 0.16 : 0.13);
}

QPalette Theme::palette() const {
    QPalette p;
    p.setColor(QPalette::Window, m_windowBg);
    p.setColor(QPalette::WindowText, m_fg);
    p.setColor(QPalette::Base, m_cardBg);
    p.setColor(QPalette::AlternateBase, m_cardHoverBg);
    p.setColor(QPalette::ToolTipBase, m_popoverBg);
    p.setColor(QPalette::ToolTipText, m_fg);
    p.setColor(QPalette::Text, m_fg);
    p.setColor(QPalette::Button, m_cardBg);
    p.setColor(QPalette::ButtonText, m_fg);
    p.setColor(QPalette::BrightText, m_fg);
    p.setColor(QPalette::Link, m_accentText);
    p.setColor(QPalette::Highlight, QColor(m_accent));
    p.setColor(QPalette::HighlightedText, QColor(accentForeground()));
    p.setColor(QPalette::PlaceholderText, m_fgMuted);
    p.setColor(QPalette::Mid, m_border);
    p.setColor(QPalette::Midlight, m_cardHoverBg);
    p.setColor(QPalette::Dark, m_borderStrong);
    p.setColor(QPalette::Disabled, QPalette::WindowText, m_fgMuted);
    p.setColor(QPalette::Disabled, QPalette::Text, m_fgMuted);
    p.setColor(QPalette::Disabled, QPalette::ButtonText, m_fgMuted);
    return p;
}

void Theme::reload() {
    refreshRounding();
    const auto paths = m_watcher.files() + m_watcher.directories();
    if (!paths.isEmpty())
        m_watcher.removePaths(paths);

    // A theme switch replaces symlinks and files, so watch the parents too and
    // re-arm after every change. Watching the nearest existing ancestor means
    // installing Omarchy later works without restarting the app.
    QString ancestor = m_directory;
    while (!QFileInfo::exists(ancestor) && ancestor != "/")
        ancestor = QFileInfo(ancestor).absolutePath();
    QStringList candidates{ancestor, QFileInfo(ancestor).absolutePath(), m_directory,
                           m_directory + "/theme", m_directory + "/theme/colors.toml"};
    candidates.removeDuplicates();
    for (const auto &path : candidates)
        if (QFileInfo::exists(path))
            m_watcher.addPath(path);

    const auto parsed = parseColorsToml(m_directory + "/theme/colors.toml");
    auto pick = [&](const QString &key, const QColor &fallback) -> QColor {
        const QString v = parsed.colors.value(key);
        return v.isEmpty() ? fallback : QColor(v);
    };

    const QString accent = parsed.colors.value("accent", "#FFD60A");
    const QColor rawBg = pick("background", QColor("#242428"));
    bool isDark = true;
    if (parsed.mode == "light")
        isDark = false;
    else if (parsed.mode == "dark")
        isDark = true;
    else if (parsed.colors.contains("background"))
        isDark = relativeLuminance(rawBg) < 0.45;

    QColor windowBg, headerBg, cardBg, cardHoverBg, cardSelectedBg, popoverBg;
    QColor fg, fgMuted, border, borderStrong;

    if (isDark) {
        const QColor fallbackWindow("#18181c");
        const QColor fallbackCard("#24242a");
        const QColor fallbackLighter("#32323a");
        fg = pick("foreground", QColor("#f2f2f5"));
        const QColor darkBg = pick("dark_background", parsed.colors.contains("background")
                                                          ? mixColors(rawBg, QColor("#000000"), 0.22)
                                                          : fallbackWindow);
        const QColor lighterBg = pick("lighter_background", parsed.colors.contains("background")
                                                                ? mixColors(rawBg, fg, 0.10)
                                                                : fallbackLighter);
        windowBg = darkBg;
        headerBg = windowBg;
        // Lift cards clearly above the window canvas so warm and cool dark
        // themes never blur into muddy tone-on-tone slabs.
        const QColor baseCard = parsed.colors.contains("background") ? rawBg : fallbackCard;
        cardBg = contrastRatio(baseCard, windowBg) >= 1.18
                     ? mixColors(baseCard, lighterBg, 0.36)
                     : mixColors(windowBg, lighterBg, 0.65);
        if (contrastRatio(cardBg, windowBg) < 1.22)
            cardBg = mixColors(windowBg, fg, 0.075);
        cardHoverBg = mixColors(cardBg, fg, 0.065);
        // Clean neutral surface lift with a whisper of accent avoids murky
        // olive/brown washes when accent is bright yellow or rust.
        cardSelectedBg = mixColors(mixColors(cardBg, fg, 0.085), QColor(accent), 0.025);
        popoverBg = mixColors(cardBg, lighterBg, 0.65);
        if (contrastRatio(popoverBg, cardBg) < 1.08)
            popoverBg = mixColors(cardBg, fg, 0.07);
        border = withAlpha(fg, 0.16);
        borderStrong = withAlpha(fg, 0.30);
        const QColor rawMuted = pick("dark_foreground", mixColors(fg, cardBg, 0.28));
        fgMuted = ensureContrast(rawMuted, cardBg, true, 7.2);
    } else {
        fg = pick("foreground", QColor("#1c1c1e"));
        const QColor baseCard = pick("background", QColor("#ffffff"));
        const QColor darkBg = pick("dark_background", mixColors(baseCard, fg, 0.05));
        windowBg = contrastRatio(baseCard, darkBg) >= 1.06 ? darkBg : mixColors(baseCard, fg, 0.05);
        headerBg = windowBg;
        cardBg = baseCard;
        cardHoverBg = mixColors(cardBg, fg, 0.045);
        // Calm neutral-tinted focus surface so selected rows never shout over hero cards.
        cardSelectedBg = mixColors(mixColors(cardBg, fg, 0.045), QColor(accent), 0.035);
        popoverBg = cardBg;
        border = withAlpha(fg, 0.15);
        borderStrong = withAlpha(fg, 0.26);
        const QColor rawMuted = pick("dark_foreground", mixColors(fg, cardBg, 0.38));
        fgMuted = ensureContrast(rawMuted, cardBg, false, 5.6);
    }

    const double pillAlpha = isDark ? 0.16 : 0.13;
    const QColor accentText = ensureContrast(QColor(accent), cardBg, isDark, isDark ? 5.8 : 5.2, pillAlpha);
    // Keep nominal green unmistakably green (never olive/amber) so Live,
    // None posted, and Go badges share one coherent semantic cue.
    QColor rawGreen = pick("green", isDark ? QColor("#57e389") : QColor("#26a269"));
    if (rawGreen.hslHue() >= 0 && rawGreen.hslHue() < 95)
        rawGreen = mixColors(rawGreen, isDark ? QColor("#5cd685") : QColor("#26a269"), 0.72);
    const double statusMinContrast = isDark ? 5.5 : 5.2;
    const QColor positive = ensureContrast(rawGreen, cardBg, isDark, statusMinContrast, pillAlpha);
    const QColor warning = ensureContrast(pick("yellow", isDark ? QColor("#f8b436") : QColor("#c67b00")), cardBg, isDark, statusMinContrast, pillAlpha);
    const QColor negative = ensureContrast(pick("red", isDark ? QColor("#ff7b63") : QColor("#c01c28")), cardBg, isDark, statusMinContrast, pillAlpha);

    const bool dirty = (isDark != m_isDark) || (accent != m_accent) || (accentText != m_accentText)
                       || (windowBg != m_windowBg) || (headerBg != m_headerBg) || (cardBg != m_cardBg)
                       || (cardHoverBg != m_cardHoverBg) || (cardSelectedBg != m_cardSelectedBg)
                       || (popoverBg != m_popoverBg) || (border != m_border) || (borderStrong != m_borderStrong)
                       || (fg != m_fg) || (fgMuted != m_fgMuted) || (positive != m_positive)
                       || (warning != m_warning) || (negative != m_negative);
    if (dirty) {
        m_isDark = isDark;
        m_accent = accent;
        m_accentText = accentText;
        m_windowBg = windowBg;
        m_headerBg = headerBg;
        m_cardBg = cardBg;
        m_cardHoverBg = cardHoverBg;
        m_cardSelectedBg = cardSelectedBg;
        m_popoverBg = popoverBg;
        m_border = border;
        m_borderStrong = borderStrong;
        m_fg = fg;
        m_fgMuted = fgMuted;
        m_positive = positive;
        m_warning = warning;
        m_negative = negative;
        emit changed();
    }
}
