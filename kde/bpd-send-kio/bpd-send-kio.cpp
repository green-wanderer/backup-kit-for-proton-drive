/*
 * bpd-send-kio - Dolphin right-click menu that shows your Proton Drive folder
 * tree as nested menus and hands the choice to bpd-send.
 *
 * A .desktop service menu can only be one level deep, which is why this is a
 * plugin. It draws the menu from CACHE_DIR/menu.tsv, written by bpd-send-menu,
 * and never touches the network: it runs while the menu is being drawn.
 */

#include <KAbstractFileItemActionPlugin>
#include <KFileItemListProperties>
#include <KPluginFactory>

#include <QAction>
#include <QDir>
#include <QFile>
#include <QHash>
#include <QIcon>
#include <QMenu>
#include <QProcess>
#include <QTextStream>
#include <QUrl>

namespace
{

QString envDir(const char *var, const QString &fallback)
{
    const QByteArray v = qgetenv(var);
    return v.isEmpty() ? QDir::homePath() + fallback : QString::fromLocal8Bit(v);
}

// The few settings this needs, from the same settings.conf the scripts read.
struct Settings {
    QString cacheDir = envDir("XDG_CACHE_HOME", QStringLiteral("/.cache")) + QStringLiteral("/bpd-backup");
    int perLevel = 60;
    int depth = 3;
};

Settings readSettings()
{
    Settings s;
    QString confDir = QString::fromLocal8Bit(qgetenv("BPD_CONF_DIR"));
    if (confDir.isEmpty()) {
        confDir = envDir("XDG_CONFIG_HOME", QStringLiteral("/.config")) + QStringLiteral("/bpd-backup");
    }
    QFile f(confDir + QStringLiteral("/settings.conf"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return s;
    }
    QTextStream in(&f);
    while (!in.atEnd()) {
        const QString line = in.readLine().trimmed();
        const int eq = line.indexOf(QLatin1Char('='));
        if (line.startsWith(QLatin1Char('#')) || eq < 0) {
            continue;
        }
        const QString key = line.left(eq).trimmed();
        QString val = line.mid(eq + 1).trimmed();
        if (val == QLatin1String("~") || val.startsWith(QLatin1String("~/"))) {
            val = QDir::homePath() + val.mid(1);
        }
        bool ok = false;
        if (key == QLatin1String("cache_dir")) {
            s.cacheDir = val;
        } else if (key == QLatin1String("menu_per_level")) {
            const int n = val.toInt(&ok);
            if (ok && n > 0) {
                s.perLevel = n;
            }
        } else if (key == QLatin1String("menu_depth")) {
            const int n = val.toInt(&ok);
            if (ok && n > 0) {
                s.depth = n;
            }
        }
    }
    return s;
}

// menu.tsv: "R root", "X path-to-bpd-send", then "N path parent name" per folder.
struct Model {
    QString root;
    QString exe;
    QHash<QString, QList<QPair<QString, QString>>> children; // parent -> (path, name)
};

Model readModel(const QString &path)
{
    Model m;
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return m;
    }
    QTextStream in(&f);
    while (!in.atEnd()) {
        const QStringList c = in.readLine().split(QLatin1Char('\t'));
        if (c.size() >= 2 && c[0] == QLatin1String("R")) {
            m.root = c[1];
        } else if (c.size() >= 2 && c[0] == QLatin1String("X")) {
            m.exe = c[1];
        } else if (c.size() >= 4 && c[0] == QLatin1String("N")) {
            m.children[c[2]].append({c[1], c[3]});
        }
    }
    return m;
}

class Builder
{
public:
    Builder(const Model &model, const Settings &settings, const QStringList &files)
        : m(model)
        , s(settings)
        , files(files)
    {
    }

    void run(const QStringList &args) const
    {
        if (!m.exe.isEmpty()) {
            QProcess::startDetached(m.exe, args + files);
        }
    }

    QAction *item(QMenu *menu, const QString &icon, const QString &text, const QStringList &args) const
    {
        QAction *a = menu->addAction(QIcon::fromTheme(icon), text);
        const Builder self = *this;
        QObject::connect(a, &QAction::triggered, menu, [self, args]() {
            self.run(args);
        });
        return a;
    }

    void level(QMenu *menu, const QString &path, int depth) const
    {
        item(menu, QStringLiteral("folder-cloud"), QObject::tr("Send here"), {QStringLiteral("--to"), path});
        item(menu, QStringLiteral("folder-new"), QObject::tr("New folder here…"), {QStringLiteral("--mkdir"), QStringLiteral("--to"), path});

        const auto kids = m.children.value(path);
        if (!kids.isEmpty()) {
            menu->addSeparator();
        }
        int shown = 0;
        for (const auto &kid : kids) {
            if (shown == s.perLevel) {
                item(menu, QStringLiteral("folder-open"),
                     QObject::tr("%1 more… Choose folder").arg(kids.size() - shown), {QStringLiteral("--pick")});
                break;
            }
            ++shown;
            if (m.children.value(kid.first).isEmpty() || depth + 1 >= s.depth) {
                item(menu, QStringLiteral("folder"), kid.second, {QStringLiteral("--to"), kid.first});
            } else {
                level(menu->addMenu(QIcon::fromTheme(QStringLiteral("folder")), kid.second), kid.first, depth + 1);
            }
        }
    }

private:
    Model m;
    Settings s;
    QStringList files;
};

} // namespace

class BpdSendKio : public KAbstractFileItemActionPlugin
{
    Q_OBJECT

public:
    BpdSendKio(QObject *parent, const QVariantList &)
        : KAbstractFileItemActionPlugin(parent)
    {
    }

    QList<QAction *> actions(const KFileItemListProperties &info, QWidget *parentWidget) override
    {
        QStringList files;
        for (const QUrl &url : info.urlList()) {
            if (!url.isLocalFile()) {
                return {};
            }
            files << url.toLocalFile();
        }
        if (files.isEmpty()) {
            return {};
        }

        const Settings settings = readSettings();
        const Model model = readModel(settings.cacheDir + QStringLiteral("/menu.tsv"));
        if (model.exe.isEmpty()) {
            return {}; // bpd-send-menu has not run yet
        }
        const Builder b(model, settings, files);

        QAction *top = new QAction(QIcon::fromTheme(QStringLiteral("folder-cloud")), QObject::tr("Send to Proton Drive"), parentWidget);
        QMenu *menu = new QMenu(parentWidget);
        top->setMenu(menu);
        b.level(menu, model.root, 0);
        menu->addSeparator();
        b.item(menu, QStringLiteral("folder-open"), QObject::tr("Choose folder…"), {QStringLiteral("--pick")});
        b.item(menu, QStringLiteral("view-refresh"), QObject::tr("Refresh folder list"), {QStringLiteral("--refresh")});

        QAction *get = new QAction(QIcon::fromTheme(QStringLiteral("folder-download")), QObject::tr("Get from Proton Drive…"), parentWidget);
        QObject::connect(get, &QAction::triggered, get, [b]() {
            b.run({QStringLiteral("--get")});
        });
        return {top, get};
    }
};

K_PLUGIN_CLASS_WITH_JSON(BpdSendKio, "bpd-send-kio.json")

#include "bpd-send-kio.moc"
