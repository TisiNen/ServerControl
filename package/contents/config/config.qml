import QtQuick
import org.kde.plasma.configuration

// The pages of the settings dialog. Each source is a file in contents/ui/.
ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "ConfigGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Servers")
        icon: "network-server-symbolic"
        source: "ConfigServers.qml"
    }
}
