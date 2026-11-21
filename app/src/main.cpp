// FlightDeck Mission Control: the Starship campaign and the launch schedule,
// read live from the flightdeck service. Launched with `flightdeck open`.

#include <QApplication>
#include <QFont>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>

#include "backend.h"
#include "symboliciconprovider.h"
#include "theme.h"
#include "translator.h"

int main(int argc, char *argv[]) {
    // Fusion honors QApplication::setPalette() live across Omarchy dark/light
    // theme switches without reading Plasma's kdeglobals, while Kirigami
    // supplies the window, banners, shadows, and placeholder primitives.
    QQuickStyle::setStyle("Fusion");

    QApplication app(argc, argv);
    app.setApplicationName("flightdeck");
    app.setApplicationVersion("0.1.0");

    // Matches the window to flightdeck.desktop, so the compositor (Wayland
    // app_id) and the launcher pick up the installed icon.
    app.setDesktopFileName("flightdeck");

    // Prefer GNOME's Adwaita Sans when installed so typography aligns with
    // GNOME HIG; falls back gracefully to the system sans-serif otherwise.
    QFont appFont("Adwaita Sans");
    appFont.setPointSize(10);
    app.setFont(appFont);

    // Installed before anything is translated, and every qsTr() binding is
    // re-evaluated when the Omarchy language changes.
    Translator translator;
    app.installTranslator(&translator);

    Theme theme;
    auto syncPlatformTheme = [&]() {
        app.setPalette(theme.palette());
        // Use Papirus icons (Papirus-Dark / Papirus), falling back to Breeze
        // for any icon not shipped by Papirus. SymbolicIconProvider tints
        // monochrome icons cleanly to the live Omarchy palette.
        QIcon::setThemeName(theme.isDark() ? "Papirus-Dark" : "Papirus");
        QIcon::setFallbackThemeName(theme.isDark() ? "breeze-dark" : "breeze");
        app.setWindowIcon(QIcon::fromTheme("flightdeck"));
    };
    syncPlatformTheme();
    QObject::connect(&theme, &Theme::changed, &app, syncPlatformTheme);

    Backend backend;

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("symbolic"), new SymbolicIconProvider());
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    engine.rootContext()->setContextProperty("translator", &translator);
    engine.rootContext()->setContextProperty("theme", &theme);
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return 1;

    return app.exec();
}
