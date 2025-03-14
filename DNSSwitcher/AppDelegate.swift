//
//  AppDelegate.swift
//  DNSSwitcher
//
//  Created by Matthew McNeeney on 02/06/2016.
//  Copyright © 2016 mattmc. All rights reserved.
//

import Cocoa
import SwiftyJSON

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    @IBOutlet weak var menu: NSMenu!
    @IBOutlet weak var versionItem: NSMenuItem!
    @IBOutlet weak var interfaceMenu: NSMenu!

    let statusItem = NSStatusBar.system.statusItem(withLength: -1)
    let configFilePath = (NSHomeDirectory() as NSString).appending("/.dnsswitcher.json")

    var config: Config?
    var lastConfigFileUpdate: NSDate?

    // MARK: - Application lifecycle

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        // Add status bar icon
        if let button = statusItem.button {
            button.image = NSImage(named: NSImage.Name("MenuIcon"))
        }
        statusItem.menu = menu

        // Set version number
        if let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as? String {
            self.versionItem.title = "v\(version)"
        }

        // Create default configuration file if required
        if !FileManager.default.fileExists(atPath: self.configFilePath) {
            self.createDefaultConfigFile()
        }

        // Make sure we know whenever the menu is opened
        self.menu.delegate = self

        // Load available network interfaces
        self.loadNetworkInterfaces()

        // Load the configuration file
        self.initMenu()
    }


    // MARK: - Network interfaces

    func loadNetworkInterfaces() {
        let command: [String] = [ "networksetup", "-listallnetworkservices" ]
        let (result, output) = runCommand(args: command)
        if result != 0 {
            print("Critical error: could not load network services")
            self.quit(nil)
            return
        }
        for interface in (output as NSString).components(separatedBy: "\n") {
            // Ignore disabled interfaces
            if (interface as NSString).contains("*") || interface == "" {
                continue
            }
            // Add the network interface to the interfaces menu
            let interfaceItem = NSMenuItem(title: interface, action: #selector(self.setInterface(_:)), keyEquivalent: "")
            self.interfaceMenu.addItem(interfaceItem)
        }
    }

    func highlightEnabledInterface() {
        var interfaceSelected = false
        for item in self.interfaceMenu.items {
            item.state = NSControl.StateValue(rawValue: 0)
            if item.title == self.config?.interface {
                item.state = NSControl.StateValue(rawValue: 1)
                interfaceSelected = true
            }
        }
        /* Failover - if no interface has been selected, set
         * the first one */
        if !interfaceSelected {
            self.config?.interface = self.interfaceMenu.items[0].title
            self.interfaceMenu.items[0].state = NSControl.StateValue(rawValue: 1)
        }
    }

    @objc func setInterface(_ item: NSMenuItem) {
        self.config?.interface = item.title
        self.highlightEnabledInterface()
        self.saveLatestConfig()
    }


    // MARK: - DNS settings

    func clearServers() {
        for item in self.menu.items {
            if item is DNSMenuItem {
                self.menu.removeItem(item)
            }
        }
    }

    func highlightCurrentDNSServers() {
        let command: [String] = [ "networksetup", "-getdnsservers", self.config!.interface! ]
        let (result, output) = self.runCommand(args: command)
        if result != 0 {
            print("Error fetching current DNS servers")
            return
        }
        var servers: [String] = []
        for s in (output as NSString).components(separatedBy: "\n") {
            if s != "" {
                servers.append(s)
            }
        }

        // Highlight the selected DNS servers in the menu
        for item in self.menu.items {
            if item is DNSMenuItem {
                item.state = NSControl.StateValue(rawValue: 0)
                let setting = (item as! DNSMenuItem).setting
                if setting?.servers! == servers {
                    item.state = NSControl.StateValue(rawValue: 1)
                }
            }
        }
    }

    @objc func setDNSServers(_ item: DNSMenuItem) {
        // Check if we have a load command to run
        if let loadCmd = item.setting.loadCmd {
            let command: [String] = (loadCmd as NSString).components(separatedBy: " ")
            let (result, output) = runCommand(args: command)
            if result != 0 {
                self.showAlert(title: "Error", message: "Load command failed with exit code \(result): \(output)", style: NSAlert.Style.critical)
                return
            }
        }

        // Change the DNS settings
        let command: [String] = [ "networksetup", "-setdnsservers", self.config!.interface! ] + item.setting.servers!
        let (result, output) = runCommand(args: command)
        if result != 0 {
            self.showAlert(title: "Error", message: "DNS change failed with exit code \(result): \(output)", style: NSAlert.Style.critical)
        }
        else {
        //  self.showAlert(title: "DNS Changed", message: "Your DNS settings have been updated successfully.", style: NSAlert.Style.warning)
        }
    }


    // MARK: - Dropdown menu

    func initMenu() {

        guard let configData = NSData(contentsOfFile: self.configFilePath) else {
            print("Critical error: configuration file failed to load")
            self.quit(nil)
            return
        }

        // Create the configuration object
        self.config = Config(data: configData)

        // Clear existing servers from the menu
        self.clearServers()

        // Add the new list of servers to the menu
        let settings = self.config!.settings!
        for i in 0...settings.count-1 {
            let setting = settings[settings.count-i-1]

            // Add the name of the DNS server as the menu title
            let item = DNSMenuItem(title: setting.name!, action: nil, keyEquivalent: "")
            item.setting = setting

            // Create the submenu
            let submenu = NSMenu()

            // Add a load button
            let loadItem = DNSMenuItem(title: "Load", action: #selector(self.setDNSServers(_:)), keyEquivalent: "")
            loadItem.setting = setting
            submenu.addItem(loadItem)

            // Add a separator
            submenu.addItem(NSMenuItem.separator())

            // Add the list of servers
            let serverTitleItem = NSMenuItem(title: "Servers:", action: nil, keyEquivalent: "")
            serverTitleItem.isEnabled = false
            submenu.addItem(serverTitleItem)
            for server in setting.servers! {
                let item = NSMenuItem(title: server, action: nil, keyEquivalent: "")
                item.indentationLevel = 1
                item.isEnabled = false
                submenu.addItem(item)
            }

            // Add the submenu to the menu item
            item.submenu = submenu

            // Add the menu item to the top of the menu
            self.menu.insertItem(item, at: 0)
        }

        /* Highlight the enabled interface */
        self.highlightEnabledInterface()

        /* Fetch the current DNS settings and highlight the selected setting in the menu if appropriate */
        self.highlightCurrentDNSServers()
    }

    func menuWillOpen(_ menu: NSMenu) {
        /* Only initialise the menu if the configuration has changed */
        if !self.checkForConfigUpdate() {
            /* In case the DNS servers have been changed, highlight the selected ones now */
            self.highlightCurrentDNSServers()
            return
        }

        /* Initialise the dropdown menu */
        self.initMenu()
    }


    // MARK: - Configuration file

    func createDefaultConfigFile() {
        // If the file doesn't exist, create it using the default
        if !FileManager.default.fileExists(atPath: self.configFilePath) {
            let defaultFilePath = Bundle.main.path(forResource: "dnsswitcher.default", ofType: "json")
            do {
                try FileManager.default.copyItem(atPath: defaultFilePath!, toPath: self.configFilePath)
            }
            catch {
                print("Critical error: failed to create default config file")
                self.quit(nil)
            }
        }
        // Else copy the contents of the default to the existing file
        let defaultFilePath = Bundle.main.path(forResource: "dnsswitcher.default", ofType: "json")
        let data = NSData(contentsOfFile: defaultFilePath!)
        data?.write(toFile: self.configFilePath, atomically: true)
    }

    func saveLatestConfig() {
        if let data = self.config?.export() {
            do {
                try data.write(toFile: self.configFilePath, atomically: true, encoding: String.Encoding.utf8)
            }
            catch {
                print("Error saving configuration file")
            }
        }
    }

    func checkForConfigUpdate() -> Bool {
        // Check when the configuration file was last modified
        var configFileAttributes: [FileAttributeKey: Any]?
        do {
            configFileAttributes = try FileManager.default.attributesOfItem(atPath: self.configFilePath)
        }
        catch _ {
            // Failover - reload the configuration file
            return true
        }
        guard let lastModification = configFileAttributes?[FileAttributeKey(rawValue: FileAttributeKey.modificationDate.rawValue)] as? NSDate else {
            // Failover - reload the configuration file
            return true
        }

        // This may be the first load
        if self.lastConfigFileUpdate == nil {
            self.lastConfigFileUpdate = lastModification
            return true
        }

        // Compare the modification dates
        let updateNeeded = (lastModification.compare(self.lastConfigFileUpdate! as Date) == ComparisonResult.orderedDescending)
        self.lastConfigFileUpdate = lastModification
        return updateNeeded
    }


    // MARK: - Actions

    @IBAction func editServers(_ sender: AnyObject) {
    //    NSWorkspace.shared.openFile(self.configFilePath)
        let url = URL(fileURLWithPath: self.configFilePath)
        NSWorkspace.shared.open(url)
    }

    @IBAction func restoreDefaultServers(_ sender: AnyObject) {
        self.createDefaultConfigFile()
        self.initMenu()
    }

    @IBAction func about(_ sender: AnyObject) {
        if let url = Bundle.main.infoDictionary!["Product Homepage"] as? String {
            NSWorkspace.shared.open(NSURL(string: url)! as URL)
        }
    }

    @IBAction func quit(_ sender: AnyObject?) {
        NSStatusBar.system.removeStatusItem(statusItem)
        NSApp.terminate(self)
    }


    // MARK: - Helpers

    func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "Ok")
        alert.runModal()
    }

    func runCommand(args: [String]) -> (result: Int32, output: String) {
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output: String = NSString(data: data, encoding: String.Encoding.utf8.rawValue)! as String
        return (task.terminationStatus, output)
    }

}
