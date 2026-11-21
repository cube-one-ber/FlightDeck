#pragma once

#include <QColor>
#include <QIcon>
#include <QPainter>
#include <QPixmap>
#include <QQuickImageProvider>
#include <QUrl>

// Renders Freedesktop symbolic theme icons (Papirus first, Breeze fallback)
// tinted via QPainter::CompositionMode_SourceIn so every monochrome icon matches
// live Omarchy colors with exact contrast under Fusion and offscreen backends.
//
// URL format: image://symbolic/<icon-name>?color=<url-encoded-#rrggbb>
class SymbolicIconProvider : public QQuickImageProvider {
public:
    SymbolicIconProvider() : QQuickImageProvider(QQuickImageProvider::Pixmap) {}

    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requestedSize) override {
        const int q = id.indexOf('?');
        const QString name = q >= 0 ? id.left(q) : id;
        QColor tint;
        if (q >= 0) {
            const QString query = id.mid(q + 1);
            const QString prefix = QStringLiteral("color=");
            if (query.startsWith(prefix))
                tint = QColor(QUrl::fromPercentEncoding(query.mid(prefix.size()).toUtf8()));
        }

        const int w = requestedSize.width() > 0 ? requestedSize.width() : 16;
        const int h = requestedSize.height() > 0 ? requestedSize.height() : 16;
        // Request at 2x logical size for crisp HiDPI rendering.
        const QSize target(w * 2, h * 2);

        QIcon icon = QIcon::fromTheme(name);
        if (icon.isNull() && name.endsWith(QStringLiteral("-symbolic")))
            icon = QIcon::fromTheme(name.left(name.size() - 9));

        QPixmap src = icon.pixmap(target);
        if (src.isNull()) {
            QPixmap empty(target);
            empty.fill(Qt::transparent);
            if (size) *size = target;
            return empty;
        }

        if (tint.isValid()) {
            QPixmap colored(src.size());
            colored.setDevicePixelRatio(src.devicePixelRatio());
            colored.fill(Qt::transparent);
            QPainter p(&colored);
            p.drawPixmap(0, 0, src);
            p.setCompositionMode(QPainter::CompositionMode_SourceIn);
            p.fillRect(colored.rect(), tint);
            p.end();
            src = colored;
        }

        if (size) *size = src.size();
        return src;
    }
};
