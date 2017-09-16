//
//  ViewController.swift
//  Glowdeck
//
//  Created by Justin Kaufman on 11/17/16.
//  Copyright © 2016 Justin Kaufman. All rights reserved.
//

import Cocoa

import CoreFoundation

import IOKit.pwr_mgt

import Foundation

import IOBluetooth
import IOBluetoothUI

import RxBluetoothKit
import RxSwift

import CoreBluetooth

import AppKit

let kIOPMAssertionTypeNoDisplaySleep = "PreventUserIdleDisplaySleep" as CFString

struct MSTCCResult{
    var targetdevice: IOBluetoothDevice? = nil
    var iserror: Bool = false
    var errorMessage: String? = nil
    var ssid: String? = nil
    var passcode: String? = nil
}


class ViewController: NSViewController, IOBluetoothDeviceInquiryDelegate, IOBluetoothRFCOMMChannelDelegate, IOBluetoothDeviceAsyncCallbacks, URLSessionDownloadDelegate, URLSessionTaskDelegate {

    
    // MARK: - Firmware update vars
    var arguments: [NSString] = []
    
    var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    
    
    var keepAwake: IOReturn = -100
    var binPath: URL = URL(string: "https://streams.io/glowdeck/firmware/images/glowdeckV3.bin")!
    var binPathString: NSString = "https://streams.io/glowdeck/firmware/images/glowdeckV3.bin"
    var fileHandle: FileHandle!
    var currentBuild: String = ""
    var installedBuild: String = ""
    var manualDisconnect: Bool = false
    var autoUpdate: Bool = false
    var firmwareSize: Int = 0
    var firmwareUpdateActive: Bool = false
    var firmwareData: Data!
    var dataPosition: Int = 0
    var blueLightMode: Bool = true
    var percentageCompleteLast: Int = 0
    var lastTransmissionTime = Date.timeIntervalSinceReferenceDate
    var downloadTask: URLSessionDownloadTask!
    var backgroundSession: URLSession!
    var uploadTimer: Timer?
    var startTime: Date!
    var lastSelectedTitle: String = "Scanning..."
    
    // MARK: - State vars
    var glowdeckBLE: Bool = false
    var glowdeckSPP: Bool = false
    var rtcTime = ""
    
    // MARK: - SPP vars
    var channel: IOBluetoothRFCOMMChannel?
    var isopen: Bool = false
    var writebuffer: NSMutableData = NSMutableData(length: 16)!
    var callback: ((MSTCCResult) -> Void)?
    var targetdevice: IOBluetoothDevice?
    
    var inquiry: IOBluetoothDeviceInquiry?
    var sppDevice: IOBluetoothDevice!
    
    
    
    // MARK: - BLE vars
    var ble: BLE!
    var bleRecv: String = ""
    var bundle = Bundle()
    var bleScanTimer: Timer?
    var bleScanHandlerTimer: Timer?
    var bleConnectTimer: Timer?
    var recoveryTimer: Timer?
    var bleConnectStatus: Bool = false
    
    // MARK: - Arduino patch vars
    var arduinoPath: URL!
    var arduinoPathString: String = "/Applications/Arduino.app"
    
    // MARK: - Interface outlets
    @IBOutlet weak var glowdeckIcon: NSImageView!
    @IBOutlet weak var btcConnectedGlowdeckField: NSTextField!
    @IBOutlet weak var btcUpdateButton: NSButton!
    @IBOutlet weak var btcConnectButton: NSButton!
    @IBOutlet weak var updateButton: NSButton!
    @IBOutlet var btcConnectIndicator: NSProgressIndicator!
    @IBOutlet weak var currentVersionLabel: NSTextField!
    @IBOutlet weak var installedVersionLabel: NSTextField!
    @IBOutlet weak var pathSelectButton: NSButton!
    @IBOutlet weak var percentCompleteField: NSTextField!
    @IBOutlet weak var connectButton: NSPopUpButton!
    @IBOutlet weak var pathField: NSTextField!
    @IBOutlet weak var updateIndicator: NSProgressIndicator!
    @IBOutlet weak var bleConnectIndicator: NSProgressIndicator!
    
    let disposeBag = DisposeBag()
    
    let      serviceUUID =      "BC2F4CC6-AAEF-4351-9034-D66268E328F0"
    let      sppServiceUUID =   "00001101 0000 1000 8000 00805F9B34FB"
    let      txCharacteristic = "06D1E5E7-79AD-4A71-8FAA-373789F7D93C"
    let      rxCharacteristic = "06D1E5E7-79AD-4A71-8FAA-373789F7D93C"
    
    var isScanInProgress = false
    var scheduler: ConcurrentDispatchQueueScheduler!
    
    var manager: BluetoothManager!

    var stateObservable: Observable<BluetoothState>!
    
    var scanningDisposable: Disposable?
    var peripheralsArray: [ScannedPeripheral] = []
    
    var scannedPeripheral: ScannedPeripheral!
    var connectedPeripheral: Peripheral?
    var servicesList: [Service] = []

    
    // MARK: - Overrides
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let timerQueue = DispatchQueue(label: "com.plsco.Glowdeck.timer")
        scheduler = ConcurrentDispatchQueueScheduler(queue: timerQueue)
        
        // Get command line parameters (if any)
        arguments = CommandLine.arguments as [NSString]
        
        // Setup assertion id for preventing sleep
        assertionID = IOPMAssertionID(0)
        
        // Setup background session for file downloads
        let backgroundSessionConfiguration = URLSessionConfiguration.background(withIdentifier: "glowdeckBackgroundSession")
        backgroundSession = Foundation.URLSession(configuration: backgroundSessionConfiguration, delegate: self, delegateQueue: OperationQueue.main)
        self.bundle = Bundle.main
        
        self.channel = IOBluetoothRFCOMMChannel()
        isopen  = false
        writebuffer = NSMutableData(length: 16)!
        callback = nil
        targetdevice = nil
        
        // SPP connection
        inquiry = IOBluetoothDeviceInquiry()
        inquiry?.delegate = self
        
        manager = BluetoothManager(queue: .main)
        
        stateObservable = manager.rx_state
        
    }
    
    override func viewWillAppear() {
        DispatchQueue.main.async {
            self.getCurrentBuild()
        }
    }
    
    
    override func viewDidAppear() {
        
        for arg in arguments {
            
            let argStr = String(arg)
            
            if argStr.range(of: ".bin") != nil {

                var compPath: NSString? = NSString()
                
                let bpString: NSString = arg
                
                bpString.completePath(into: &compPath, caseSensitive: true, matchesInto: nil, filterTypes: nil)
                
                if (compPath?.length)! > 1 {
                    
                    binPathString = compPath!
                    
                }
                else {
                    
                    binPathString = arg
                    
                }
            
                self.pathField.stringValue = "\(binPathString)"
               
                binPath = (NSURL(fileURLWithPath: "\(binPathString)", isDirectory: false) as URL)

                self.autoUpdate = true
                
                break
                
            }

        
        }

        /*
        let sppList = self.listMSTCCDevice()
        
        if !sppList.isEmpty {
            
            for spp in sppList {
                
                if let name = spp.nameOrAddress {
                    
                    if name.contains("deck") || name.contains("BC") || name.contains("GD") || name.contains("BlueCreation") {
                        
                        sppDevice = spp
                        
                        if !sppDevice.isConnected() {
                            
                            // sppDevice.openConnection()
                            
                            glowdeckSPP = true
                            
                            //sppDevice.addToFavorites()
                            
                            self.sppDevice.register(forDisconnectNotification: nil, selector: #selector(self.sppDeviceDidDisconnect))
                            
                            print("[SPP] Connected to \(sppDevice.name!)")
                            
                            // btcConnectedGlowdeckField.stringValue = sppDevice.name
                            
                            self.connectButton.addItem(withTitle: sppDevice.name!)
                            
                            self.connectButton.selectItem(withTitle: sppDevice.name!)
                            
                            self.updateButton.isEnabled = true
                            
                            btcConnectButton.title = "Disconnect"
                            
                        }
                        else {
                            
                            self.sppDevice.register(forDisconnectNotification: nil, selector: #selector(self.sppDeviceDidDisconnect))
                            
                            print("[SPP] Connected to \(sppDevice.name!)")
                            
                            // btcConnectedGlowdeckField.stringValue = sppDevice.name
                            
                            self.connectButton.addItem(withTitle: sppDevice.name!)
                            
                            self.connectButton.selectItem(withTitle: sppDevice.name!)
                            
                            self.updateButton.isEnabled = true
                            
                            btcConnectButton.title = "Disconnect"
                            
                        }
                        
                        break
                        
                    }
                    
                }
                
                //print("SPP: \(spp.nameOrAddress)")
                
                
                
            }
            
        }
        else {
            
            // print("SPP Pair...")
            
            self.sppPair()
            
        }
        
        */
         self.sppPair()
        
        // self.bleScan()
        
    }
    
    override var representedObject: Any? {
        didSet {
            
        }
    }
    
    
    func stopScanning() {
        
        scanningDisposable?.dispose()
        
        isScanInProgress = false
        
    }
    
    func startScanning() {
        
        print("startScanning:")
        
        isScanInProgress = true

        scanningDisposable = manager.rx_state
            
            .timeout(4.0, scheduler: scheduler)
            
            .take(1)
            
            .flatMap { _ in self.manager.scanForPeripherals(withServices: nil, options: nil) } // [CBUUID(string: self.serviceUUID)], options: nil) }
            
            .subscribeOn(MainScheduler.instance)
            
            .subscribe(onNext: {
                
                self.addNewScannedPeripheral($0)
                
            }, onError: { error in
                
        })
        
    }
    
    func addNewScannedPeripheral(_ peripheral: ScannedPeripheral) {
        
        print("addNewScannedPeripheral:")
        let mapped = self.peripheralsArray.map { $0.peripheral }
        
        if let indx = mapped.index(of: peripheral.peripheral) {
            
            self.peripheralsArray[indx] = peripheral
            
        }
        else {
            
            self.peripheralsArray.append(peripheral)
            
        }
        
        DispatchQueue.main.async {
            self.bleScanHandler()
        }
        
        if self.peripheralsArray.isEmpty {
            updateButton.isEnabled = false
        }
        
    }
    
    
    // MARK: - Arduino installer actions
    @IBAction func consumerButton(_: AnyObject) {
        let alert = NSAlert()
        alert.addButton(withTitle: "OK")
        alert.messageText = "Glowdeck for macOS"
        alert.informativeText = "This application is in development and will be released in early 2017. Stay tuned."
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    @IBAction func developerButton(_: AnyObject) {
        let alert = NSAlert()
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.messageText = "Are you ready?"
        alert.informativeText = "You must have the following prerequisites installed before continuing:\n\n1:  Arduino v1.6.12\n\n2:  Teensyduino v1.31\n\nPress OK to proceed."
        alert.alertStyle = .informational
        alert.beginSheetModal(for: super.view.window!, completionHandler: { (modalResponse) -> Void in
            if modalResponse == NSAlertFirstButtonReturn {
                //self.editionLabel.stringValue = "Glowdeck Developer Edition"
                //self.consumerBtn.isHidden = true
                //self.orDivLeft.isHidden = true
                //self.orDivRight.isHidden = true
                //self.orLabel.isHidden = true
                self.browseFile()
            }
            else {
                return
            }
        })

    }
    @IBAction func installPressed(_: AnyObject) {
        let alert = NSAlert()
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.messageText = "Glowdeck Developer Edition"
        alert.informativeText = "This will add the Glowdeck board to your Arduino installation.\n\nWhile this software is in beta, it is strongly recommended that you back up your current Arduino environment PRIOR TO pressing OK."
        alert.alertStyle = .informational
        alert.beginSheetModal(for: super.view.window!, completionHandler: { (modalResponse) -> Void in
            if modalResponse == NSAlertFirstButtonReturn {
                self.patchArduino()
            }
            else {
                return
            }
        })
    }
    
    // MARK: - SPP actions
    @IBAction func btcConnectPressed(_: AnyObject) {
        sppPair()
    }
    @IBAction func btcUpdatePressed(_: AnyObject) {
        downloadFirmware()
    }
    
    // MARK: - BLE actions
    @IBAction func updatePressed(_: AnyObject) {
        recoveryTimer?.invalidate()
        self.downloadFirmware()
    }
    @IBAction func selectFirmwarePressed(_: AnyObject) {
        self.getFirmware()
    }
    @IBAction func connectButtonPressed(_: AnyObject) {
        let selected = connectButton.titleOfSelectedItem!
        let index = connectButton.indexOfItem(withTitle: selected)
        let item = connectButton.item(at: index)
        connectButton.select(item)
        connectButton.synchronizeTitleAndSelectedItem()
        if selected.characters.count > 1 {
            if selected == "Disconnect" {
                if lastSelectedTitle.range(of: "deck") != nil {
                    self.connectButton.removeItem(withTitle: lastSelectedTitle)
                    self.ble.peripherals.removeAll()
                }
                manualDisconnect = true
                if ble.activePeripheral != nil {
                    if ble.activePeripheral?.state == .connected {
                        if self.ble.disconnectFromPeripheral(peripheral: ble.activePeripheral!) {
                            print("Disconnecting...")
                        }
                        self.connectButton.item(withTitle: "Disconnect")?.title = "Scanning..."
                        self.connectButton.item(withTitle: "Scanning...")?.image = NSImage(named: "NSStatusPartiallyAvailable")!
                        self.connectButton.selectItem(withTitle: "Scanning...")
                        self.connectButton.synchronizeTitleAndSelectedItem()
                        self.lastSelectedTitle = "Scanning..."
                        DispatchQueue.main.async {
                            self.bleScan()
                        }
                    }
                }
            }
            else if selected != "Scanning..." {
                self.bleConnectTimer?.invalidate()
                self.bleScanTimer?.invalidate()
                self.bleScanHandlerTimer?.invalidate()
                self.recoveryTimer?.invalidate()
                if ble.peripherals.count > 0 {
                    for i in 0..<ble.peripherals.count {
                        if ble.peripherals[i].name == selected {
                            DispatchQueue.main.async {
                                if self.ble.connectToPeripheral(peripheral: self.ble.peripherals[i]) {
                                    self.connectButton.item(withTitle: "Scanning...")?.title = "Disconnect"
                                    self.connectButton.item(withTitle: "Disconnect")?.image = NSImage(named: "NSStatusUnavailable")!
                                    self.connectButton.selectItem(withTitle: selected)
                                    self.connectButton.synchronizeTitleAndSelectedItem()
                                    self.lastSelectedTitle = selected
                                    print("Connecting to \(selected)...")
                                }
                            }
                            return
                        }
                    }
                }
                else {
                    DispatchQueue.main.async {
                        self.bleScan()
                    }
                }
            }
        }
    }
    @IBAction func helpButtonPressed(_: AnyObject) {
        NSWorkspace.shared().open(NSURL(string: "https://streams.io/glowdeck")! as URL)
    }
    
    func connectRoutine(_ selected: String) {
        
        let current = connectButton.titleOfSelectedItem!
        
        if current != selected {
            
            connectButton.selectItem(withTitle: selected)
            
        }
        
        let index = connectButton.indexOfItem(withTitle: selected)
        
        let item = connectButton.item(at: index)
        
        connectButton.select(item)
        
        connectButton.synchronizeTitleAndSelectedItem()
        
        if selected.characters.count > 1 {
            
            if selected == "Disconnect" {
                
                manualDisconnect = true
                
                if ble.activePeripheral != nil {
                    
                    if ble.activePeripheral?.state == .connected {
                        
                        if self.ble.disconnectFromPeripheral(peripheral: ble.activePeripheral!) {
                            
                            print("Disconnecting...")
                            
                        }
                        
                        self.connectButton.item(withTitle: "Disconnect")?.title = "Scanning..."
                        
                        self.connectButton.item(withTitle: "Scanning...")?.image = NSImage(named: "NSStatusPartiallyAvailable")!
                        
                        self.connectButton.selectItem(withTitle: "Scanning...")
                        
                        self.connectButton.synchronizeTitleAndSelectedItem()
                        
                        DispatchQueue.main.async {
                            
                            self.bleScan()
                            
                        }
                        
                    }
                    
                }
                
            }
            else if selected != "Scanning..." {
                
                self.bleConnectTimer?.invalidate()
                self.bleScanTimer?.invalidate()
                self.bleScanHandlerTimer?.invalidate()
                self.recoveryTimer?.invalidate()
                
                
                
                if ble.peripherals.count > 0 {
                    
                    for i in 0..<self.peripheralsArray.count {
                        
                        if self.peripheralsArray[i].peripheral.name == selected {
                            
                            DispatchQueue.main.async {
                                
                                self.stopScanning()
                                
                                self.bleConnect(peripheral: self.peripheralsArray[i])
                                    
                                self.connectButton.item(withTitle: "Scanning...")?.title = "Disconnect"
                                    
                                self.connectButton.item(withTitle: "Disconnect")?.image = NSImage(named: "NSStatusUnavailable")!
                                    
                                self.connectButton.selectItem(withTitle: selected)
                                    
                                self.connectButton.synchronizeTitleAndSelectedItem()
                                    
                                print("Connecting to \(selected)...")
                                
                                
                                
                            }
                            
                            return
                            
                        }
                        
                    }
                    
                }
                else {
                    
                    DispatchQueue.main.async {
                        
                        self.bleScan()
                        
                    }
                    
                }
                
            }
            
        }
        
    }
    
    func monitorDisconnection(for peripheral: Peripheral) {
        
        manager.monitorDisconnection(for: peripheral)
            
            .subscribe(onNext: { [weak self] (peripheral) in
                
                print("Peripheral Disconnected!")
                //let alert = UIAlertController(title: "Disconnected!", message: "Peripheral Disconnected", preferredStyle: .alert)
                
                //alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                
                //self?.present(alert, animated: true, completion: nil)
                
            }).addDisposableTo(disposeBag)
        
    }
    
    func downloadServices(for peripheral: Peripheral) {
        
        peripheral.discoverServices(nil)
            
            .subscribe(onNext: { services in
                
                self.servicesList = services
                
                // self.servicesTableView.reloadData()
                
            }).addDisposableTo(disposeBag)
        
    }
    
    func bleConnect(peripheral: ScannedPeripheral) {
        
        manager.connect(peripheral.peripheral)
            
            .subscribe(onNext: { [weak self] in
            
                guard let `self` = self else { return }
                
                self.bleConnectIndicator.stopAnimation(nil)
                
                self.connectedPeripheral = $0
                
                self.monitorDisconnection(for: $0)
                
                self.downloadServices(for: $0)
                
            }).addDisposableTo(disposeBag)
        
    }
    
    func getFirmware() {
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputTextField.placeholderString = "Complete URL for .bin file"
        inputTextField.stringValue = "https://streams.io/glowdeck/firmware/images/glowdeckV3.bin"
        
        let alert = NSAlert()
        alert.messageText = "Select Firmware"
        alert.informativeText = "Enter URL of firmware (.bin file) to upload or select OK to use the most recent build."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Local File")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        alert.accessoryView = inputTextField
        
        alert.beginSheetModal(for: super.view.window!, completionHandler: { (modalResponse) -> Void in
            // 'OK' Pressed
            if modalResponse == NSAlertFirstButtonReturn {
                let input = inputTextField.stringValue
                // Valid URL
                if input.characters.count > 0 && (input.range(of: ":") != nil && input.range(of: "//") != nil && input.range(of: ".") != nil && input.range(of: "http") != nil && input.range(of: ".bin") != nil) {
                    self.binPathString = input as NSString
                    self.binPath = URL(string: self.binPathString as String)!
                    DispatchQueue.main.async {
                        self.pathField.stringValue = self.binPathString as String
                    }
                }
                // Invalid URL
                else {
                    let alert = NSAlert()
                    alert.addButton(withTitle: "OK")
                    alert.messageText = "Invalid URL"
                    alert.informativeText = "You must enter a valid URL where a .bin file can be downloaded. To upload a local .bin file, select 'Local File' instead."
                    alert.alertStyle = .informational
                    alert.runModal()
                }
            }
            
            // 'Local File' Pressed
            else if modalResponse == NSAlertSecondButtonReturn {
                DispatchQueue.main.async {
                    self.browseFirmware()
                }
            }
        })
    }
    func repairFirmware() {
        let dialog = NSOpenPanel()
        dialog.title                   = "Select File"
        dialog.message                 = "There was an issue locating the build. Navigate to the .bin on your computer to proceed."
        dialog.directoryURL            = URL(fileURLWithPath: "/tmp", isDirectory: true)
        dialog.showsResizeIndicator    = true
        dialog.showsHiddenFiles        = true
        dialog.canChooseDirectories    = false
        dialog.canCreateDirectories    = false
        dialog.allowsMultipleSelection = false
        dialog.treatsFilePackagesAsDirectories = false
        dialog.canSelectHiddenExtension = true
        dialog.allowedFileTypes        = ["bin"]
        if dialog.runModal() == NSModalResponseOK {
            let result = dialog.url
            if result != nil {
                self.binPath = result!
                self.binPathString = result!.path as NSString
                self.pathField.stringValue = self.binPathString as String
                self.autoUpdate = true
            }
            else {
                self.autoUpdate = false
            }
        }
    }
    func browseFirmware() {
        let dialog = NSOpenPanel()
        dialog.title                   = "Select Firmware File"
        dialog.message                 = "Navigate to the .bin file you wish to upload:"
        dialog.directoryURL            = URL(fileURLWithPath: "/tmp", isDirectory: true)
        dialog.showsResizeIndicator    = true
        dialog.showsHiddenFiles        = true
        dialog.canChooseDirectories    = false
        dialog.canCreateDirectories    = false
        dialog.allowsMultipleSelection = false
        dialog.treatsFilePackagesAsDirectories = false
        dialog.canSelectHiddenExtension = true
        dialog.allowedFileTypes        = ["bin"]
        if dialog.runModal() == NSModalResponseOK {
            let result = dialog.url
            if result != nil {
                self.binPath = result!
                self.binPathString = result!.path as NSString
                self.pathField.stringValue = self.binPathString as String
            }
        }
        else {
            return
        }
    }
    func getCurrentBuild() {
        let url = URL(string: "https://streams.io/buckets/scripts/getCurrentBuild.php")
        let task = URLSession.shared.dataTask(with: url!, completionHandler: { (data, response, error) in
            DispatchQueue.main.async(execute: {
                self.updateCurrentBuild(data!)
            })
        })
        task.resume()
    }
    func updateCurrentBuild(_ buildData: Data) {
        if let json = try! JSONSerialization.jsonObject(with: buildData, options: .allowFragments) as? NSDictionary {
            if let build = json["version"] as? String {
                currentBuild = build
                currentVersionLabel.stringValue = "v\(currentBuild)"
                print("Current build: \(currentBuild)")
            }
            else {
                currentBuild = "Error"
                print("Error getting current build")
            }
        }
    }
    func checkRecovery() {
        if installedBuild == "" {
            self.blueLightMode = true
            self.updateButton.stringValue = "Recover"
            if UserDefaults.standard.object(forKey: "recoverAlert") == nil && !autoUpdate {
                let alert = NSAlert()
                alert.addButton(withTitle: "OK")
                alert.messageText = "Glowdeck Recovery"
                alert.informativeText = "Your Glowdeck appears to be in recovery mode.\n\nIf this is not true, you can disregard this message.\n\nOtherwise, you must enter 'BLUE-LIGHT MODE' before proceeding (if you haven't already).\n\nSTEPS TO ENTER BLUE-LIGHT MODE:\n\n1. Unplug power from Glowdeck.\n\n2. Hold down the front button/edge of Glowdeck as you plug power back in.\n\n3. All the lights should be blue and you can release the front button/edge.\n\n4. Now re-connect (if necessary) and then click Update."
                alert.alertStyle = .informational
                alert.runModal()
                
                UserDefaults.standard.set(true, forKey: "recoverAlert")
            }
        }
        else {
            self.updateButton.stringValue = "Update"
            self.blueLightMode = false
        }
        
        self.updateButton.isEnabled = true
    }
    
    func updateTime() {
        var dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYY-MM-dd HH:mm:ss | zzz"
        dateFormatter.timeZone = TimeZone.current
        let tempRtc = dateFormatter.string(from: Date())
        let comps = tempRtc.components(separatedBy: " | ")
        if !comps.isEmpty {
            rtcTime = comps[0]
        }
        else {
            dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "YYYY-MM-dd HH:mm:ss"
            rtcTime = dateFormatter.string(from: Date())
        }
        // print("rtcTime: \(rtcTime)")
        // Ex: RECV BLE 2015-01-31 03:04:55
    }
    func transmitTime() {
        updateTime()
        DispatchQueue.main.async {
            self.bleSend("TIM:\(self.rtcTime)^\r")
        }
    }
}

// MARK: - Bluetooth LE methods
extension ViewController {
    
    func bleScan() {

        print("bleScan:")
        
        if !self.isScanInProgress {
            
            bleConnectTimer?.invalidate()
            
            bleConnectIndicator.isHidden = false
            
            bleConnectIndicator.isIndeterminate = true
            
            bleConnectIndicator.usesThreadedAnimation = true
            
            bleConnectIndicator.startAnimation(nil)
            
            self.startScanning()
            
        }
        
        // let serviceId: CBUUID = CBUUID(string: serviceUUID)
        
    }
    
    func bleScanHandler() {
        
        print("bleScanHandler:")
        
        var currentItems: [String] = []
        
        if peripheralsArray.isEmpty {
            
            self.connectButton.autoenablesItems = true
            
            self.connectButton.isEnabled = true
            
            for item in peripheralsArray {
                
                let per = item.peripheral
                
                guard let name = per.name else { continue }
                
                print("BLE Device: \(name)")
                
                if name.contains("deck") || name.contains("GD") || name.contains("BC") || name.contains("BlueCreation") {
                    
                    currentItems.append(name)
                    
                    if !connectButton.itemTitles.contains(name) {
                        
                        connectButton.addItem(withTitle: name)
                        
                        connectButton.item(withTitle: name)?.image = NSImage(named: "NSStatusAvailable")!
                        
                    }
                    
                }
                
            }
            
        }
        
        if !currentItems.isEmpty {
            
            for item in (connectButton.itemTitles).reversed() {
            
                if item != "Scanning..." && item != "Disconnect" && !currentItems.contains(item) {
                
                    connectButton.removeItem(withTitle: item)
                
                }
            
            }
            
            connectButton.isEnabled = true
            
            if connectButton.numberOfItems == 2 && !manualDisconnect {
            
                for i in 0..<connectButton.itemTitles.count {
                
                    if connectButton.itemTitles[i].range(of: "deck") != nil || connectButton.itemTitles[i].range(of: "GD") != nil {
                    
                        self.bleConnectTimer?.invalidate()
                        
                        self.bleScanTimer?.invalidate()
                        
                        self.bleScanHandlerTimer?.invalidate()
                        
                        self.recoveryTimer?.invalidate()
                        
                        DispatchQueue.main.async {
                        
                            self.connectButton.selectItem(withTitle: self.connectButton.itemTitles[i])
                            
                            self.connectButton.synchronizeTitleAndSelectedItem()
                            
                            self.connectRoutine(self.connectButton.itemTitles[i])
                        
                        }
                        
                        return
                    
                    }
                
                }
            
            }
        
        }
        else {
            
            connectButton.removeAllItems()
            
            connectButton.addItem(withTitle: "Scanning...")
            
            connectButton.item(withTitle: "Scanning...")?.image = NSImage(named: "NSStatusPartiallyAvailable")!
            
            connectButton.selectItem(withTitle: "Scanning...")
            
        }
        
        connectButton.synchronizeTitleAndSelectedItem()
        
        bleScanTimer = Timer.scheduledTimer(timeInterval: 4.0, target: self, selector: #selector(self.bleScan), userInfo: nil, repeats: false)
    
    }
    func bleDidUpdateState() {
        // print("bleDidUpdateState")
    }
    func bleDidConnectToPeripheral() {
        let name = ble.activePeripheral!.name!
        let item = self.connectButton.item(withTitle: name)
        self.connectButton.select(item)
        self.connectButton.synchronizeTitleAndSelectedItem()
        self.blueLightMode = true
        self.bleConnectTimer?.invalidate()
        self.bleScanTimer?.invalidate()
        self.bleScanHandlerTimer?.invalidate()
        self.recoveryTimer?.invalidate()
        self.bleConnectIndicator.stopAnimation(nil)
        self.bleConnectIndicator.isHidden = true
        self.bleConnectStatus = true
        self.glowdeckBLE = true
        if autoUpdate {
            self.bleSend("GFU^\r")
            let delay = 6.125 * Double(NSEC_PER_SEC)
            let time = DispatchTime.now() + Double(Int64(delay)) / Double(NSEC_PER_SEC)
            DispatchQueue.main.asyncAfter(deadline: time) { () -> Void in
                self.downloadFirmware()
            }
            return
        }
        self.recoveryTimer = Timer.scheduledTimer(timeInterval: 6.5, target: self, selector: #selector(self.checkRecovery), userInfo: nil, repeats: false)
    }
    func bleDidDisconenctFromPeripheral() {
        self.blueLightMode = true
        self.ble.activePeripheral = nil
        self.ble.peripherals.removeAll()
        self.glowdeckBLE = false
        self.updateButton.isEnabled = false
        self.bleConnectStatus = false
        self.updateButton.isEnabled = false
        self.updateIndicator.doubleValue = 0.0
        self.percentCompleteField.stringValue = ""
        self.installedBuild = ""
        self.installedVersionLabel.stringValue = ""
        connectButton.removeAllItems()
        connectButton.addItem(withTitle: "Scanning...")
        connectButton.item(withTitle: "Scanning...")?.image = NSImage(named: "NSStatusPartiallyAvailable")!
        connectButton.selectItem(withTitle: "Scanning...")
        connectButton.synchronizeTitleAndSelectedItem()
        connectButton.isEnabled = true
        
        let delay = 1.25 * Double(NSEC_PER_SEC)
        let time = DispatchTime.now() + Double(Int64(delay)) / Double(NSEC_PER_SEC)
        DispatchQueue.main.asyncAfter(deadline: time) { () -> Void in
            self.bleConnectIndicator.isHidden = false
            self.bleConnectIndicator.startAnimation(nil)
            self.bleScan()
        }
    }
    func bleDidReceiveData(data: NSData?) {
        let bleTemp: String = NSString(data: data! as Data, encoding: String.Encoding.utf8.rawValue)! as String
        bleRecv += bleTemp
        if bleRecv.range(of: "^") == nil {
            return
        }
        bleRecv = bleRecv.replacingOccurrences(of: "\n", with: "")
        print("[RX] \(bleRecv.replacingOccurrences(of: "\r", with: ""))")
        bleReceiveHandler(bleRecv)
        bleRecv = ""
    }
    func bleReceiveHandler(_ rx: String) {
        var cmd = ""
        var setParams: [String] = []
        
        if rx.range(of: ":") != nil {
            //recoveryMode = false
            //bluetoothData = true
            let components = rx.components(separatedBy: ":")
            if components.count >= 2 {
                cmd = components[0]
                for i in 1..<components.count {
                    setParams.append(components[i].replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: ""))
                }
            }
        }
        else {
            cmd = rx.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
        }
        
        switch cmd {
            
        case "SYNC":
            // print("Sync requested, sending status command")
            
            DispatchQueue.main.async {
                self.transmitTime()
            }
            
            self.runWithDelay(3.1275) {
                self.bleSend("VER^\r")
            }
            
        case "POW":
            print("[BLE] \(rx)")
            /*
            if !setParams.isEmpty {
                if setParams[0] == "1" {
                    if self.sleepModeButton.alpha != 1.0 {
                        self.sleepModeButton.alpha = 1.0
                    }
                }
                else {
                    if self.sleepModeButton.alpha == 1.0 {
                        self.sleepModeButton.alpha = 0.625
                    }
                }
            }
            */
        case "COL":
            print("[BLE] \(rx)")
            /*
            if !setParams.isEmpty {
                if setParams.count == 3 {
                    if let col0 = Int(setParams[0]) {
                        if let col1 = Int(setParams[1]) {
                            if let col2 = Int(setParams[2]) {
                                selectedColor[0] = col0
                                selectedColor[1] = col1
                                selectedColor[2] = col2
                                self.colorPickerButton.setTitleColor(UIColor(red: CGFloat(col0) / CGFloat(255.0), green: CGFloat(col1) / CGFloat(255.0), blue: CGFloat(col2) / CGFloat(255.0), alpha: 1.0), for: UIControlState())
                                if col0 + col1 + col2 == 0 {
                                    self.foundationButton.backgroundColor = self.foundationButton.backgroundColor?.withAlphaComponent(0.0)
                                }
                                else {
                                    self.foundationButton.backgroundColor = UIColor(red: CGFloat(col0) / CGFloat(255.0), green: CGFloat(col1) / CGFloat(255.0), blue: CGFloat(col2) / CGFloat(255.0), alpha: 0.625)
                                }
                            }
                        }
                    }
                }
            }
            */
        case "CHG":
            print("[BLE] \(rx)")
            /*
            if !setParams.isEmpty {
                if setParams[0] == "0" {
                    if self.chargeSurfaceButton.alpha == 1.0 {
                        self.chargeSurfaceButton.alpha = 0.625
                    }
                }
                else {
                    if self.chargeSurfaceButton.alpha != 1.0 {
                        self.chargeSurfaceButton.alpha = 1.0
                    }
                }
            }
            */
        case "VER":
            self.glowdeckBLE = true
            self.blueLightMode = false
            self.updateButton.isEnabled = true
            
            if !setParams.isEmpty {
                installedBuild = setParams[0]
                installedVersionLabel.stringValue = "v\(installedBuild)"
                
                DispatchQueue.main.async {
                    self.bleSend("VER:OK^\r")
                }
            }
        case "TIM":
            //print("Time requested")
            self.transmitTime()
            
        /*
        case "WTR":
            //print("Weather requested")
            bluetoothData = true
            self.updateWeather(true)
            
        case "MSL":
            if !setParams.isEmpty {
                if setParams[0] == "0" {
                    if musicSyncSwitch.alpha == 1.0 { //.currentImage == UIImage(named: "led_rainbow")! {
                        self.musicSyncSwitch.alpha = 0.625  //.setImage(UIImage(named: "led_on")!, for: .normal)
                        self.setSpeakerButtonBackgroundColor(color: UIColor.clear.withAlphaComponent(0.0))
                    }
                }
                else {
                    if musicSyncSwitch.alpha != 1.0 { //.currentImage == UIImage(named: "led_on")! {
                        self.musicSyncSwitch.alpha = 1.0 //.setImage(UIImage(named: "led_rainbow")!, for: .normal)
                        self.colorPickerButton.alpha = 0.625
                        self.setSpeakerButtonBackgroundColor(color: UIColor.cyan.withAlphaComponent(0.3725))
                    }
                }
            }

        case "DBR":
            if !setParams.isEmpty {
                if let value = Int(setParams[0]) {
                    lcdBrightness = Int(setParams[0])!
                    brightnessSlider.setValue(Float(value), animated: true)
                }
            }
        case "DBA":
            if !setParams.isEmpty {
                if let value = Int(setParams[0]) {
                    if value == 1 {
                        if self.autoBrightButton.alpha != 1.0 {
                            self.autoBrightButton.alpha = 1.0
                        }
                    }
                    else {
                        if self.autoBrightButton.alpha == 1.0 {
                            self.autoBrightButton.alpha = 0.625
                        }
                    }
                }
            }
        case "BAT":
            DispatchQueue.main.async {
                self.bleSend("BAT:\(self.batteryLevel)^\r")
            }
        */
        case "GFU":
            self.glowdeckBLE = true
            self.blueLightMode = false
            self.installedBuild = self.currentBuild
            self.installedVersionLabel.stringValue = self.currentVersionLabel.stringValue
            self.updateButton.isEnabled = true
            if UserDefaults.standard.object(forKey: "firstUpdate") == nil && !autoUpdate {
                let alert = NSAlert()
                alert.addButton(withTitle: "OK")
                alert.messageText = "Update Complete"
                alert.informativeText = "Glowdeck successfully updated to v\(currentBuild)!"
                alert.alertStyle = .informational
                alert.runModal()
                UserDefaults.standard.set(true, forKey: "firstUpdate")
            }
        case "ANM":
            print("[BLE] \(rx)")
            /*
            if !setParams.isEmpty {
                if setParams[0] == "-1" {
                    animationIndex = -1
                }
                else {
                    if let ind = Int(setParams[0]) {
                        animationIndex = ind
                    }
                }
            }
            */
        case "BTC":
            print("[BLE] \(rx)")
            /*
            if !setParams.isEmpty {
                if setParams[0] == "0" {
                    bluetoothAudio = false
                    bluetoothMap = false
                    musicSyncSwitch.alpha = 0.625
                    self.navigationItem.rightBarButtonItem?.title = "audio"
                    self.navigationItem.rightBarButtonItem?.setTitleTextAttributes([NSFontAttributeName: UIFont(name: "Avenir-Light", size: 16.5)!], for: .normal)
                }
                else {
                    musicSyncSwitch.isEnabled = true
                    bluetoothAudio = true
                    self.navigationItem.rightBarButtonItem?.title = ""
                    self.runWithDelay(17.5) {
                        if !self.bluetoothMap {
                            self.navigationItem.rightBarButtonItem?.title = "streams"
                            self.navigationItem.rightBarButtonItem?.setTitleTextAttributes([NSFontAttributeName: UIFont(name: "Avenir-Light", size: 16.5)!], for: .normal)
                            //self.navigationItem.rightBarButtonItem?.isEnabled = true
                        }
                        else {
                            self.navigationItem.rightBarButtonItem?.title = ""
                            /// self.navigationItem.rightBarButtonItem?.isEnabled = true
                        }
                        self.runWithDelay(1.0) {
                            self.bleSend("MAP:2^\r")
                            //self.device?.sendCommand("STATUS")
                        }
                        
                    }
                }
            }
            */
        case "MAP":
            print("[BLE] \(rx)")
            /*
            if !setParams.isEmpty {
                if setParams[0] == "0" {
                    bluetoothMap = false
                    if bluetoothAudio {
                        self.navigationItem.rightBarButtonItem?.title = "streams"
                        self.navigationItem.rightBarButtonItem?.setTitleTextAttributes([NSFontAttributeName: UIFont(name: "Avenir-Light", size: 18.5)!], for: .normal)
                    }
                }
                else if setParams[0] == "1" {
                    UserDefaults.standard.set(true, forKey: "mapAlert")
                    if !bluetoothMap {
                        bluetoothMap = true
                        self.navigationItem.rightBarButtonItem?.title = ""
                        self.navigationItem.rightBarButtonItem?.setTitleTextAttributes([NSFontAttributeName: UIFont(name: "Avenir-Light", size: 18.5)!], for: .normal)
                        
                        if mapEnabled != "1" {
                            mapEnabled = "1"
                            UserDefaults.standard.set(mapEnabled, forKey: "mapEnabled")
                            UserDefaults.standard.synchronize()
                            if UserDefaults.standard.object(forKey: "userOnboarded") != nil {
                                DispatchQueue.main.async {
                                    self.syncUser()
                                }
                            }
                        }
                    }
                    if ble.activePeripheral?.state != .connected {
                        self.navigationItem.rightBarButtonItem?.title = "connect"
                        self.navigationItem.rightBarButtonItem?.setTitleTextAttributes([NSFontAttributeName: UIFont(name: "Avenir-Light", size: 18.5)!], for: .normal)
                    }
                    else {
                        self.navigationItem.rightBarButtonItem?.title = ""
                        self.navigationItem.rightBarButtonItem?.setTitleTextAttributes([NSFontAttributeName: UIFont(name: "Avenir-Light", size: 18.5)!], for: .normal)
                    }
                }
            }
            */
        default:
            print("[BLE] \(rx)")
            self.glowdeckBLE = true
        }
    }
    func bleSend(_ sendCmd: String) {
        
        if firmwareUpdateActive && !sendCmd.contains("GFU") { return }
        
        var sendData: Data!
        
        // Count bytes in transmit string
        let totalBytes = sendCmd.characters.count
        
        var remainingBytes = totalBytes
        
        // Transmit string too long to send in single transmission (20 byte limit over BLE)
        if (totalBytes > 19) {
            
            var holder = sendCmd
            
            // Send transmit string in 20-byte sections (until entire string is transmitted)
            repeat {
                
                let tempString1 = holder.substring(to: holder.characters.index(holder.startIndex, offsetBy: 19))       // Bytes: 0  - 20
                let tempString2 = holder.substring(from: holder.characters.index(holder.startIndex, offsetBy: 19))     // Bytes: 20 - End
                
                
                if sppDevice != nil {
                    sppSend(tempString1)
                }
                else {
                    // Send 20 bytes of transmit string
                    sendData = Data(bytes: UnsafePointer<UInt8>(tempString1), count: tempString1.characters.count)
                    ble.write(sendData as NSData)
                }
                
                
                remainingBytes = tempString2.characters.count
                
                // Still more than 20 bytes left to transmit...
                if remainingBytes > 19 {
                    
                    // Trim the bytes we sent from our transmit string
                    holder = tempString2
                    
                }
                // Not more than 20 bytes left to transmit (i.e. send final transmission)
                else {
                    
                    if sppDevice != nil {
                        sppSend(tempString2)
                    }
                    else {
                        sendData = Data(bytes: UnsafePointer<UInt8>(tempString2), count: tempString2.characters.count)
                        ble.write(sendData as NSData)
                    }
                    
                    remainingBytes = 0
                    
                    break
                    
                }
                
            } while (remainingBytes > 0)
            
        }
        // Transmit string does not exceed 20 bytes, send in single transmission
        else {
            
            if sppDevice != nil {
                sppSend(sendCmd)
            }
            else {
                sendData = Data(bytes: UnsafePointer<UInt8>(sendCmd), count: sendCmd.characters.count)
                ble.write(sendData as NSData)
            }
        }
        
    }
    
    func blePut(_ transmit: NSMutableData) {
        let data: Data = transmit as Data
        ble.write(data as NSData)
    }
    
}

// MARK: - Bluetooth SPP methods
extension ViewController {
    
    func sppPair() {
        
        let deviceSelector = IOBluetoothDeviceSelectorController.deviceSelector()
        
        deviceSelector?.setHeader("Pair With Glowdeck")
        
        //deviceSelector?.setOptions()
        
        let sppServiceUUID = IOBluetoothSDPUUID.uuid32(kBluetoothSDPUUID16ServiceClassSerialPort.rawValue)
        
        if deviceSelector == nil {
            
            print("Error - unable to allocate IOBluetoothDeviceSelectorController")
            
            return
            
        }
        
        deviceSelector?.addAllowedUUID(sppServiceUUID)
        
        if (deviceSelector?.runModal() != Int32(kIOBluetoothUISuccess)) {
            
            print("User has cancelled the device selection.")
            
        }
        
        guard let deviceArray = deviceSelector?.getResults(), deviceArray.count > 0 else {
            print("Error - no selected device. This should never happen.")
            return
        }
        
        for dev in deviceArray {
            
            guard let device = dev as? IOBluetoothDevice else { continue }
            
            let deviceName = device.nameOrAddress!
            
            print("SPP Device: \(deviceName)")
            
            if deviceName.contains("deck") {
                
                sppDevice = device
                
                break
                
            }
            
        }
        
        //if sppDevice != nil {
        //    print("connecting to sppdevice")
        //    self.connect(device: sppDevice)
        //}
        
        if sppDevice == nil {
            print("no sppdevice!")
            return
        }
        
        // sppDevice = deviceArray![0] as! IOBluetoothDevice
        
        let sppServiceRecord = sppDevice.getServiceRecord(for: sppServiceUUID)
        

        if (sppServiceRecord == nil) {
            print("Error - no spp service in selected device. This should never happen since the selector forces the user to select only devices with spp.")
            return
        }
        
        var rfcommChannelID: BluetoothRFCOMMChannelID = 0
        
        if (sppServiceRecord?.getRFCOMMChannelID(&rfcommChannelID) != kIOReturnSuccess) {
            print("Error - no spp service in selected device. This should never happen an spp service must have an rfcomm channel id.")
            return
        }
        
        
        if (sppDevice.openRFCOMMChannelSync(&channel, withChannelID: rfcommChannelID, delegate: self) != kIOReturnSuccess) && sppDevice == nil {
            
            // Something went bad (looking at the error codes I can also say what, but for the moment let's not dwell on
            // those details). If the device connection is left open close it and return an error:
            print("Error - open sequence failed.")
            
            return
            
        }
        else {
        
            glowdeckSPP = true
            
            //sppDevice.addToFavorites()
            
            self.sppDevice.register(forDisconnectNotification: nil, selector: #selector(self.sppDeviceDidDisconnect))
            
            print("[SPP] Connected to \(sppDevice.name!)")
            
            // btcConnectedGlowdeckField.stringValue = sppDevice.name
            
            self.connectButton.addItem(withTitle: sppDevice.name!)
            
            self.connectButton.selectItem(withTitle: sppDevice.name!)
                
            self.updateButton.isEnabled = true
            
            btcConnectButton.title = "Disconnect"
        
        }
        
    }
    func sppDeviceDidDisconnect() {
        // sppDevice = nil
        glowdeckSPP = false
        btcConnectButton.title = "Connect"
        btcConnectedGlowdeckField.stringValue = ""
        print("[SPP] Disconnected")
    }

    func sppDfuMode() {
        self.sppSend("GFU^\r")
        let delay = 2.5 * Double(NSEC_PER_SEC)
        let time = DispatchTime.now() + Double(Int64(delay)) / Double(NSEC_PER_SEC)
        DispatchQueue.main.asyncAfter(deadline: time) { () -> Void in
            self.glowdeckSPP = true
            self.downloadFirmware()
        }
    }
    
    /*
    func sppSend(_ message: String) {
        print("[TX] \(message)")
        let data = message.data(using: String.Encoding.utf8)
        let length = data!.count
        let dataPointer = UnsafeMutableRawPointer.allocate(bytes: length, alignedTo: 1)
        (data as NSData?)?.getBytes(dataPointer,length: length)
        channel?.writeSync(dataPointer, length: UInt16(length))
    }
    */
    
    
    func sppPut(_ data: Data) {
        
        var copy = data
        
        channel?.writeSync(&copy, length: UInt16(copy.count))
        
        /*
        print("[TX] \(data.description)")
        
        let length = data.count
        
        let dataPointer = UnsafeMutableRawPointer.allocate(bytes: length, alignedTo: 1)
        
        (data as NSData?)?.getBytes(dataPointer,length: length)
        
        channel?.writeSync(dataPointer, length: UInt16(length))
        */
        
    }
    func sppSend(_ message: String) {
        
        let string: NSString = message as NSString
        
        print("[SPP TX] \(string)")
        
        var data = string.data(using: String.Encoding.utf8.rawValue)!
        
        var buffer = [UInt8](repeating: 0, count: Int(data.count) + 1)
        
        for i in 0..<data.count {
            buffer[i] = data[i]
        }
        
        buffer[data.count] = 13
        
        channel?.writeSync(&buffer, length: UInt16(data.count) + 1)
        
    }
    
    func sendMessage(_ message: String) {
        
        /*
        let data = message.data(using: String.Encoding.utf8)
        let length = data!.count
        let dataPointer = UnsafeMutableRawPointer.allocate(bytes: length, alignedTo: 1)
        (data as NSData?)?.getBytes(dataPointer,length: length)
 
        

        
        var sendData = Data(bytes: UnsafePointer<UInt8>(message), count: message.characters.count)
        
        let ptr = UnsafeMutableRawPointer.allocate(bytes: message.characters.count, alignedTo: MemoryLayout<String>.alignment)
        
        ptr.storeBytes(of: <UInt8>(message), as: UInt8.self)
        
        //sendData.withUnsafeBytes {
        
        // }
        
        channel?.writeSync(ptr, length: UInt16(message.characters.count))
        
        

        let argsCount = message.utf8.count + 1
        var argsBuffer: [UInt8] = []
        argsBuffer.reserveCapacity(argsCount)
        argsBuffer.append(contentsOf: message.utf8)
        var bytesPointer = UnsafeMutableRawPointer.allocate(bytes: argsBuffer.count, alignedTo: 1)
        
        //let result = message.withCString(argsBuffer)  //withCString(message, bytesPointer)
        
        
        
        
        let count = message.utf8.count// .utf8CString.count
        let stride = MemoryLayout<String>.stride
        let alignment = MemoryLayout<String>.alignment
        let byteCount = stride * count
        
        
        do {
            
            print("Raw pointers")
            
            
            let pointer = UnsafeMutableRawPointer.allocate(bytes: count, alignedTo: alignment)
   
            defer {
                pointer.deallocate(bytes: byteCount, alignedTo: alignment)
            }
            
    
            pointer.storeBytes(of: message.utf8, as: UTF8Char.self)
            
            pointer.advanced(by: stride).storeBytes(of: 6, as: Int.self)
            
            pointer.load(as: Int.self)
            
            pointer.advanced(by: stride).load(as: Int.self)
            
            // 6
            let bufferPointer = UnsafeRawBufferPointer(start: pointer, count: byteCount)
            for (index, byte) in bufferPointer.enumerated() {
                print("byte \(index): \(byte)")
            }
        }
        
        
        // bytesPointer.storeBytes(of: argsBuffer, as: UInt8.self)
        
 
        
        
        let ptr = UnsafeMutableRawPointer(argsBuffer.baseAddress!).bindMemory(to: CChar.self, capacity: argsBuffer.count)
        
        var cStrings: [UnsafeMutablePointer<CChar>?] = argsOffsets.map { ptr + $0 }
        
        cStrings[cStrings.count - 1] = nil
        
        return body(cStrings)
 
        
        
        
        
        
        
        
        
        
        
        
        
        
        //channel?.setSerialParameters(9600, dataBits: 0, parity: OFF, stopBits: 0)
        
        var cs = (message as NSString).utf8String
        
        
        strData.withUnsafeBytes { (bytes: UnsafePointer<CChar>) -> Void in
            print("\(bytes[1])")  //exp: access as c string
        }
 
        
        let bytesPointer = UnsafeMutableRawPointer(&cs)
        
        // UnsafeMutableRawPointer.allocate(bytes: message.characters.count, alignedTo: 1)
        // bytesPointer.storeBytes(of: message, as: UInt8.self)
        
        channel?.writeSync(bytesPointer, length: UInt16(message.characters.count))
        */
    }
   
    
    func rfcommChannelWriteComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                                    refcon: UnsafeMutableRawPointer!,
                                    status error: IOReturn)
    {
        if( error != kIOReturnSuccess)
        {
            print("Failed to send data. code = \(error)")
            self.targetdevice!.closeConnection()
            self.isopen = false
            return
        }
    }
    /*
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                                   status error: IOReturn)
    {
        if( error != kIOReturnSuccess)
        {
            simpleerror("open RFCOMM Channel Error. code = \(error)")
            self.targetdevice!.closeConnection()
            self.isopen = false
            return
        }
        if( channel!.isOpen() )
        {
            let cmdata = Data(bytes: [1,0,0])
            writebuffer.setData(cmdata)
            let ret3 = channel!.writeAsync(writebuffer.mutableBytes, length: 3, refcon : nil)
            if( ret3 != kIOReturnSuccess)
            {
                simpleerror("Failed to send data. code = \(ret3)")
                self.targetdevice!.closeConnection()
                self.isopen = false
                return
            }
        }
        else
        {
            // 多分こないはず
            simpleerror("Channel is not opened")
            self.targetdevice!.closeConnection()
            self.isopen = false
            return
        }
    }
    */
    
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel?, status error: IOReturn) {
        
        if error != kIOReturnSuccess {
            
            print("Error - Failed to open the RFCOMM channel")
            
        }
        else {
            
            print("rfcommChannelOpenComplete")
            
            let delay = 6.5 * Double(NSEC_PER_SEC)
            
            let time = DispatchTime.now() + Double(Int64(delay)) / Double(NSEC_PER_SEC)
            
            DispatchQueue.main.asyncAfter(deadline: time) { () -> Void in
                
                self.sppDfuMode()
                
            }
            
        }
        
    }
 
    
    func remoteNameRequestComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        print("remoteNameRequestComplete:")
    }
    
    func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        print("connectionComplete:")
    }
    
    func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        
        if (status != kIOReturnSuccess) {
            
            print("SPD Query Failed. code = \(status)")
            
            device.closeConnection()
            
            self.isopen = false
            
            return
            
        }
        
        
        // MS-TCCのGUID
        // let uuid : [UInt8] = [0x23, 0x2e, 0x51, 0xd8, 0x91, 0xff, 0x4c, 0x24, 0xac, 0x0f, 0x9e, 0xe0, 0x55, 0xda, 0x30, 0xa5]
        
        let uuid : [UInt8] = [0x00, 0x00, 0x11, 0x01, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB]
        
        let spduuid = IOBluetoothSDPUUID(bytes: uuid, length: 16)
        
        // MS-TCCのサービス取得
        let sr = device.getServiceRecord(for: spduuid)
        
        if( sr == nil )
        {
            // 更新したらMS-TCCのサービスが見つからなかった
            print("This Device doesn't support MS-TCC now.")
            device.closeConnection()
            self.isopen = false
            return
        }
        var rfcommid = BluetoothRFCOMMChannelID()
        sr?.getRFCOMMChannelID(&rfcommid)
        let ret2 = device.openRFCOMMChannelAsync( &channel, withChannelID: rfcommid, delegate: self)
        if( ret2 != kIOReturnSuccess)
        {
            print("open RFCOMM Channel Error. code = \(ret2)")
            device.closeConnection()
            self.isopen = false
            return
        }
    }
    
    
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel?, data dataPointer: UnsafeMutableRawPointer?, length dataLength: Int) {
    
        let message = String(bytesNoCopy: dataPointer!, length: Int(dataLength), encoding: String.Encoding.utf8, freeWhenDone: false)
        
        print("[SPP RX] \(message ?? "<Unknown>")")
        
    }
 
    func deviceInquiryComplete(sender: IOBluetoothDeviceInquiry, error: IOReturn, aborted: Bool) {
        let sppDevices = sender.foundDevices()
        if !(sppDevices?.isEmpty)! {
            print("sppDevices: \(String(describing: sppDevices))")
            for spp in sppDevices! {
                if let gdSpp = spp as? IOBluetoothDevice {
                    gdSpp.getAddress()
                }
            }
        }
    }
    
    
    func dataFromString(_ input: String) -> NSData {
        let data = input.data(using: String.Encoding.utf8)
        let nsData = NSData(data: data!)
        return nsData
    }

 }

// SPPPPPPP
extension ViewController {
    
    func listMSTCCDevice() -> Array<IOBluetoothDevice> {
        
        var ans = Array<IOBluetoothDevice>()
        
        for i in IOBluetoothDevice.pairedDevices() {
            
            let device = i as! IOBluetoothDevice

            let uuid : [UInt8] = [0x00, 0x00, 0x11, 0x01, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB]
            
            let spduuid = IOBluetoothSDPUUID(bytes: uuid, length: 16)
            
            let sr = device.getServiceRecord(for: spduuid)
            
            if (sr != nil) {
                
                ans.append(device)
                
            }
            
        }
        
        return ans
        
    }
    
    /*
    func connect(devicename: String, callback: ((MSTCCResult) -> Void)? = nil) -> Bool {
        
        for i in IOBluetoothDevice.pairedDevices() {
            
            let device = i as! IOBluetoothDevice
            
            if (device.name == devicename) {
                
                return connect(device: device, callback: callback)
                
            }
            
        }
        
        simpleerror("the target device is not paired")
        
        return false
        
    }
    
     
    func connect(device: IOBluetoothDevice, callback: ((MSTCCResult) -> Void)? = nil) -> Bool {
        
        if (self.isopen) {
            
            simpleerror("Error: in operating", callback: callback)
            
            return false
            
        }
        
        let ret1 = device.openConnection()
        
        if (ret1 == kIOReturnSuccess) {
            
            self.isopen  = true
            
            self.callback = callback
            
            self.targetdevice = device
            
            device.performSDPQuery(self)
            
        }
        else {
            
            simpleerror("open connect failed. code = \(ret1)", callback: callback)
            
        }
        
        return self.isopen
        
    }
    
     
    func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        
        // SPDの情報更新完了
        if (status != kIOReturnSuccess) {
            
            simpleerror("SPD Query Failed. code = \(status)")
            
            device.closeConnection()
            
            self.isopen = false
            
            return
            
        }
        
        
        // MS-TCCのGUID
        // let uuid : [UInt8] = [0x23, 0x2e, 0x51, 0xd8, 0x91, 0xff, 0x4c, 0x24, 0xac, 0x0f, 0x9e, 0xe0, 0x55, 0xda, 0x30, 0xa5]
        
        let uuid : [UInt8] = [0x00, 0x00, 0x11, 0x01, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB]
        
        let spduuid = IOBluetoothSDPUUID(bytes: uuid, length: 16)
        
        // MS-TCCのサービス取得
        let sr = device.getServiceRecord(for: spduuid)
        
        if( sr == nil )
        {
            // 更新したらMS-TCCのサービスが見つからなかった
            simpleerror("This Device doesn't support MS-TCC now.")
            device.closeConnection()
            self.isopen = false
            return
        }
        var rfcommid = BluetoothRFCOMMChannelID()
        sr?.getRFCOMMChannelID(&rfcommid)
        let ret2 = device.openRFCOMMChannelAsync( &channel, withChannelID: rfcommid, delegate: self)
        if( ret2 != kIOReturnSuccess)
        {
            simpleerror("open RFCOMM Channel Error. code = \(ret2)")
            device.closeConnection()
            self.isopen = false
            return
        }
    }
    
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                           data dataPointer: UnsafeMutableRawPointer!,
                           length dataLength: Int)
    {
        let buf = UnsafeBufferPointer(start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength)
        let datas = Array(buf)
        var index = 0
        if( datas[0] == 2 )
        {
            var result = MSTCCResult()
            result.iserror = false
            result.errorMessage = ""
            
            index = 3
            while UInt8(index) < datas[2] {
                
                if( datas[index] == 2 )
                {
                    // SSID
                    result.ssid = getStringFromArray( datas, start: index + 3, length: Int(datas[index + 2]))
                    //                    System.Text.Encoding.ASCII.GetString()
                }
                else if( datas[index] == 4 )
                {
                    result.passcode = getStringFromArray( datas, start: index + 3, length: Int(datas[index + 2]))
                    // passphrase
                }
                index = index + Int(datas[index + 2]) + 3
            }
            
            if( self.callback != nil )
            {
                callback!(result)
            }
            self.isopen = false
        }
        else
        {
            simpleerror("MS-TCC Error!\(datas[0])") // todo
        }
        channel!.close()
        self.targetdevice!.closeConnection()
    }
    
    func rfcommChannelWriteComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                                    refcon: UnsafeMutableRawPointer!,
                                    status error: IOReturn)
    {
        if( error != kIOReturnSuccess)
        {
            simpleerror("Failed to send data. code = \(error)")
            self.targetdevice!.closeConnection()
            self.isopen = false
            return
        }
    }
    
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                                   status error: IOReturn)
    {
        if( error != kIOReturnSuccess)
        {
            simpleerror("open RFCOMM Channel Error. code = \(error)")
            self.targetdevice!.closeConnection()
            self.isopen = false
            return
        }
        if( channel!.isOpen() )
        {
            let cmdata = Data(bytes: [1,0,0])
            writebuffer.setData(cmdata)
            let ret3 = channel!.writeAsync(writebuffer.mutableBytes, length: 3, refcon : nil)
            if( ret3 != kIOReturnSuccess)
            {
                simpleerror("Failed to send data. code = \(ret3)")
                self.targetdevice!.closeConnection()
                self.isopen = false
                return
            }
        }
        else
        {
            // 多分こないはず
            simpleerror("Channel is not opened")
            self.targetdevice!.closeConnection()
            self.isopen = false
            return
        }
    }
    
    func simpleerror(_ errormessage: String, callback: ((MSTCCResult) -> Void)? = nil) {
        
        print("simpleerror: \(errormessage)")
        
        if (callback != nil) {
            var result = MSTCCResult()
            result.iserror = true
            result.errorMessage = errormessage
            callback!( result )
        }
        else if (self.callback != nil)  {
            var result = MSTCCResult()
            result.iserror = true
            result.errorMessage = errormessage
            self.callback!( result )
            self.callback = nil
        }
    }
    
    func getStringFromArray(_ datas: Array<UInt8>, start: Int, length: Int) -> String
    {
        let strarray = datas[start..<(start+length)]
        //        strarray.append(0)
        var byteBuffer = [UInt8]()
        strarray.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            byteBuffer += bytes
        }
        let str = String(bytes: byteBuffer, encoding: String.Encoding.ascii)
        return str!
    }
    
     
    func connectionComplete(_ device: IOBluetoothDevice!,
                            status: IOReturn)
    {
    }
    
     
    func remoteNameRequestComplete(_ device: IOBluetoothDevice!,
                                   status: IOReturn)
    {
    }
    */
    
}

// MARK: - Firmware loader methods
extension ViewController {
    func downloadFirmware() {
        self.updateButton.title = "Wait..."
        self.connectButton.isEnabled = false
        self.updateButton.isEnabled = false
        self.recoveryTimer?.invalidate()
        self.bleConnectTimer?.invalidate()
        self.bleScanTimer?.invalidate()
        self.bleScanHandlerTimer?.invalidate()
        self.bleConnectIndicator.stopAnimation(nil)
        self.bleConnectIndicator.isHidden = true
        if !self.blueLightMode || autoUpdate {
            self.bleSend("GFU^\r")
            self.blueLightMode = true
        }
        self.firmwareUpdateActive = true
        self.pathSelectButton.isEnabled = false
        self.updateIndicator.startAnimation(nil)
        
        keepAwake = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Uploading firmware to Bluetooth peripheral" as CFString!, &assertionID)
        
        if keepAwake == kIOReturnSuccess {
            print("System keepAwake assertion succeeded!")
        }
        
        // Non-local file
        if self.binPathString.contains("http") {
            downloadTask = backgroundSession.downloadTask(with: binPath)
            downloadTask.resume()
        }
        // Local file
        else {
            let binURL = URL(fileURLWithPath: "\(binPathString)")
            
            //let binFile: FileHandle = try! FileHandle(forReadingAtPath: binPathString as String)
            if let binFile = try? FileHandle(forReadingFrom: binURL) {
                let data: Data = binFile.readDataToEndOfFile()
                DispatchQueue.main.async {
                    binFile.closeFile()
                }
                self.updateIndicator.doubleValue = 0.01
                self.firmwareData = NSData(data: data) as Data
                self.enterBootloader()
            }
            else {
                self.repairFirmware()
            }
        }
    }
    
    func enterBootloader() {
        updateIndicator.startAnimation(self)
        self.bleSend("GFU^\r")
        let delay = 4.0 * Double(NSEC_PER_SEC)
        let time = DispatchTime.now() + Double(Int64(delay)) / Double(NSEC_PER_SEC)
        DispatchQueue.main.asyncAfter(deadline: time) { () -> Void in
            self.transmitFirmwareHeader()
        }
    }
    
    func transmitFirmwareHeader() {
        firmwareSize = firmwareData.count
        var SZ1 = UInt8((firmwareSize >> 24) & 0xFF)
        var SZ2 = UInt8((firmwareSize >> 16) & 0xFF)
        var SZ3 = UInt8((firmwareSize >> 8) & 0xFF)
        var SZ4 = UInt8((firmwareSize >> 0) & 0xFF)
        var G: UInt8 = 0x47
        var L: UInt8 = 0x4c
        var O: UInt8 = 0x4f
        var W: UInt8 = 0x57
        let headerBlock: NSMutableData = NSMutableData()
        headerBlock.append(&G, length: MemoryLayout<UInt8>.size)
        headerBlock.append(&L, length: MemoryLayout<UInt8>.size)
        headerBlock.append(&O, length: MemoryLayout<UInt8>.size)
        headerBlock.append(&W, length: MemoryLayout<UInt8>.size)
        headerBlock.append(&SZ1, length: MemoryLayout<UInt8>.size)
        headerBlock.append(&SZ2, length: MemoryLayout<UInt8>.size)
        headerBlock.append(&SZ3, length: MemoryLayout<UInt8>.size)
        headerBlock.append(&SZ4, length: MemoryLayout<UInt8>.size)
        var SPACE: UInt8 = 0x20
        for _ in 0 ..< 12 { headerBlock.append(&SPACE, length: MemoryLayout<UInt8>.size) }
        
        if sppDevice != nil {
            sppPut(headerBlock as Data)
        }
        else {
            blePut(headerBlock)
        }
        
        dataPosition = 0
        let delay = 3.625 * Double(NSEC_PER_SEC)
        let time = DispatchTime.now() + Double(Int64(delay)) / Double(NSEC_PER_SEC)
        DispatchQueue.main.asyncAfter(deadline: time) { () -> Void in
            self.transmitFirmware()
        }
    }
    
    func updateTimers() {
        let uploadProgress: Double = Double(dataPosition)/Double(firmwareSize)
        updateIndicator.doubleValue = uploadProgress
        percentCompleteField.stringValue = "\(Int(uploadProgress*100))%"
    }

    func transmitFirmware() {
        if dataPosition == 0 {
            startTime = Date()
            uploadTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.updateTimers), userInfo: nil, repeats: true)
            self.percentCompleteField.stringValue = "0%"
        }
        let remainingData: Int = Int(firmwareSize) - dataPosition
        if remainingData <= 0 {
            autoUpdate = false
            uploadTimer?.invalidate()
            updateButton.stringValue = "Finishing"
            updateIndicator.doubleValue = 1.0
            percentageCompleteLast = 0
            installedVersionLabel.stringValue = ""
            let delay = 6.025 * Double(NSEC_PER_SEC)
            let time = DispatchTime.now() + Double(Int64(delay)) / Double(NSEC_PER_SEC)
            DispatchQueue.main.asyncAfter(deadline: time) { () -> Void in
                self.updateIndicator.doubleValue = 0.0
                self.percentCompleteField.stringValue = ""
                self.firmwareUpdateActive = false
                self.updateIndicator.stopAnimation(self)
                self.pathSelectButton.isEnabled = true
                self.installedBuild = ""
                self.updateButton.title = "Update"
                self.connectButton.isEnabled = true
                IOPMAssertionRelease(self.assertionID)
                self.keepAwake = -100
            }
            return
        }
        var blockSize: Int = remainingData
        var padSize: Int = 0
        if blockSize > 20 { blockSize = 20 }
        if remainingData < 20 { padSize = 20 - remainingData }
        let end = dataPosition + blockSize
        var block = firmwareData.subdata(in: dataPosition..<end)
        var SPACE: UInt8 = 0x20
        for _ in 0..<padSize { block.append(&SPACE, count: MemoryLayout<UInt8>.size) }
        let putBlock: NSMutableData = NSMutableData(data: block)
        if sppDevice != nil {
            sppPut(putBlock as Data)
        }
        else {
            blePut(putBlock)
        }
        dataPosition += 20
        perform(#selector(self.transmitFirmware), with: nil, afterDelay: 0.03675)
    }
    
}

// MARK: - File download methods
extension ViewController {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        downloadTask = nil
        
        if error != nil {
            print(error!.localizedDescription)
        }
        else {
            print("Successfully downloaded file")
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        self.updateIndicator.doubleValue = 0.01
        let data = try! Data(contentsOf: location)
        self.firmwareData = NSData(data: data) as Data
        self.enterBootloader()
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Float(totalBytesWritten)/Float(totalBytesExpectedToWrite)
        print("Download progress: \(progress)")
    }
}

// MARK: - Arduino patch methods
extension ViewController {
    func browseFile() {
        let dialog = NSOpenPanel()
        dialog.title                   = "Select Arduino"
        dialog.message                 = "Navigate to the Arduino installation you wish to update:"
        dialog.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        dialog.showsResizeIndicator    = true
        dialog.showsHiddenFiles        = true
        dialog.canChooseDirectories    = false
        dialog.canCreateDirectories    = false
        dialog.allowsMultipleSelection = false
        dialog.treatsFilePackagesAsDirectories = false
        dialog.canSelectHiddenExtension = true
        dialog.allowedFileTypes        = ["app"]
        if dialog.runModal() == NSModalResponseOK {
            let result = dialog.url
            if result != nil {
                //self.editionLabel.stringValue = "Click Install to continue..."
                //self.developerBtn.isEnabled = false
                //self.arduinoPath = result
                //self.arduinoPathString = result!.path
                //pathField.stringValue = self.arduinoPathString
                //self.pathLabel.isHidden = false
                //self.pathField.isHidden = false
                //self.installButton.isHidden = false
                //self.progressWheel.isHidden = true
            }
        }
        else {
            return
        }
    }
    func patchArduino() {
        // self.editionLabel.stringValue = "Updating Arduino..."
        //pathField.isEnabled = false
        //glowdeckIcon.isHidden = true
        //installButton.isHidden = true
        //progressWheel.isHidden = false
        //progressWheel.startAnimation(nil)
        
        let glowdeckPath: String = "\(bundle.resourcePath!)/glowdeck"
        let targetGlowdeckPath: String = "\(arduinoPathString)/Contents/Java/hardware/teensy/avr/cores/glowdeck"
        
        let toolsPath: String = "\(bundle.resourcePath!)/tools"
        let targetToolsPath: String = "\(arduinoPathString)/Contents/Java/hardware/tools"
        
        let filemgr = FileManager.default
        
        print("glowdeckPath: \(glowdeckPath)")
        print("targetGlowdeckPath: \(targetGlowdeckPath)")
        
        
        // ADD glowdeck CORE FOLER
        do {
            try filemgr.copyItem(atPath: glowdeckPath, toPath: targetGlowdeckPath)
            print("Added glowdeck core folder")
        }
        catch let error as NSError {
            print("\(error.localizedDescription)")
        }
        catch {
            print("General error - \(error)")
        }
        
        // ADD tools FILES
        do {
            try filemgr.copyItem(atPath: "\(toolsPath)/avrdude", toPath: "\(targetToolsPath)/avrdude")
            try filemgr.copyItem(atPath: "\(toolsPath)/build-mingw32.sh", toPath: "\(targetToolsPath)/build-mingw32.sh")
            try filemgr.copyItem(atPath: "\(toolsPath)/DFU_demo", toPath: "\(targetToolsPath)/DFU_demo")
            try filemgr.copyItem(atPath: "\(toolsPath)/Glowdeck.sh", toPath: "\(targetToolsPath)/Glowdeck.sh")
            try filemgr.copyItem(atPath: "\(toolsPath)/GlowdeckIcon.icns", toPath: "\(targetToolsPath)/GlowdeckIcon.icns")
            try filemgr.copyItem(atPath: "\(toolsPath)/GlowdeckUp", toPath: "\(targetToolsPath)/GlowdeckUp")
            try filemgr.copyItem(atPath: "\(toolsPath)/mcopy", toPath: "\(targetToolsPath)/mcopy")
            try filemgr.copyItem(atPath: "\(toolsPath)/mktinyfat", toPath: "\(targetToolsPath)/mktinyfat")
            try filemgr.copyItem(atPath: "\(toolsPath)/null", toPath: "\(targetToolsPath)/null")
            try filemgr.copyItem(atPath: "\(toolsPath)/RemoveDrive", toPath: "\(targetToolsPath)/RemoveDrive")
            try filemgr.copyItem(atPath: "\(toolsPath)/RemoveDrive.txt", toPath: "\(targetToolsPath)/RemoveDrive.txt")
            print("Added glowdeck core folder")
        }
        catch let error as NSError {
            print("\(error.localizedDescription)")
        }
        catch {
            print("General error - \(error)")
        }
        
        // UPDATE tools FOLDER
        do {
            try filemgr.copyItem(atPath: toolsPath, toPath: targetToolsPath)
            print("Updated tools folder")
        }
        catch let error as NSError {
            print("\(error.localizedDescription)")
        }
        catch {
            print("General error - \(error)")
        }
        
        // ADD PLATFORM.TXT LINES
        let platformFile = "\(bundle.resourcePath!)/avr/platform.txt"
        let platformText = try! String(contentsOf: URL(fileURLWithPath: platformFile), encoding: String.Encoding.utf8)
        let targetPlatformPath: String = "\(arduinoPathString)/Contents/Java/hardware/teensy/avr/platform.txt"
        let platformUrl: URL = URL(fileURLWithPath: targetPlatformPath)
        
        print("Updating platform.txt file...")
        let platformHandle = try! FileHandle(forWritingTo: platformUrl)
        platformHandle.truncateFile(atOffset: 0)
        
        let platformData = platformText.data(using: String.Encoding.utf8)!
        platformHandle.write(platformData)
        platformHandle.closeFile()
        
        
        // ADD BOARDS.TXT LINES
        let boardsFile = "\(bundle.resourcePath!)/avr/boards.txt"
        let boardsText = try! String(contentsOf: URL(fileURLWithPath: boardsFile), encoding: String.Encoding.utf8)
        let targetBoardsPath: String = "\(arduinoPathString)/Contents/Java/hardware/teensy/avr/boards.txt"
        let boardsUrl: URL = URL(fileURLWithPath: targetBoardsPath)
        
        print("Updating boards.txt file...")
        let fileHandle = try! FileHandle(forWritingTo: boardsUrl)
        fileHandle.seekToEndOfFile()
        
        let boardsData = boardsText.data(using: String.Encoding.utf8)!
        fileHandle.write(boardsData)
        fileHandle.closeFile()
        
        print("Updates complete!")
        
        //progressWheel.stopAnimation(nil)
        
        let alert = NSAlert()
        alert.addButton(withTitle: "OK")
        alert.messageText = "Installation Complete"
        alert.informativeText = "You can now quit this application and select Glowdeck from the boards menu in Arduino."
        alert.alertStyle = .informational
        alert.runModal()
        
        //self.editionLabel.stringValue = "Select an edition to setup:"
        //progressWheel.isHidden = true
        glowdeckIcon.isHidden = false
        //installButton.isHidden = false
        pathField.isEnabled = true
        //pathLabel.isHidden = true
        pathField.isHidden = true
        //installButton.isHidden = true
        //consumerBtn.isHidden = false
        //self.orDivLeft.isHidden = false
        //self.orDivRight.isHidden = false
        //self.orLabel.isHidden = false
        //self.developerBtn.isEnabled = true
    }
}

extension ViewController {
    func runWithDelay(_ delay: TimeInterval, block: @escaping ()->()) {
        let time = DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
        DispatchQueue.main.asyncAfter(deadline: time, execute: block)
    }
}

extension String {
    func normalizedPath() -> String {
        var path = self
        if !(path as NSString).isAbsolutePath {
            path = FileManager.default.currentDirectoryPath + "/" + path
        }
        return (path as NSString).standardizingPath
    }
}
