QT += core gui quick quickcontrols2 testlib
CONFIG += c++17 testcase
TARGET = flightdeck_tests
TEMPLATE = app

INCLUDEPATH += ../src

HEADERS += ../src/backend.h ../src/theme.h
SOURCES += flightdeck_tests.cpp ../src/backend.cpp ../src/theme.cpp
