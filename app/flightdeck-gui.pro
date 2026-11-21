QT += core gui widgets qml quick quickcontrols2

CONFIG += c++17 release
TARGET = flightdeck-gui
TEMPLATE = app

HEADERS += \
    src/backend.h \
    src/symboliciconprovider.h \
    src/theme.h \
    src/translator.h

SOURCES += \
    src/main.cpp \
    src/backend.cpp \
    src/theme.cpp \
    src/translator.cpp

RESOURCES += src/resources.qrc
