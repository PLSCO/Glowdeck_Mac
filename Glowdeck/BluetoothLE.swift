//
//  BluetoothLE.swift
//  Glowdeck
//
//  Created by Justin Kaufman on 11/17/16.
//  Copyright © 2016 Justin Kaufman. All rights reserved.
//

import Foundation
import CoreBluetooth
import IOBluetooth
import IOBluetoothUI


protocol BLEDelegate {
    func bleDidUpdateState()
    func bleDidConnectToPeripheral()
    func bleDidDisconenctFromPeripheral()
    func bleDidReceiveData(data: NSData?)
}

class BLE: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var serviceUUID = "BC2F4CC6-AAEF-4351-9034-D66268E328F0"
    private var sppServiceUUID = "00001101 0000 1000 8000 00805F9B34FB"
    private var txCharacteristic = "06D1E5E7-79AD-4A71-8FAA-373789F7D93C"
    private var rxCharacteristic = "06D1E5E7-79AD-4A71-8FAA-373789F7D93C"
    
    public var delegate: BLEDelegate?
    public var centralManager: CBCentralManager!
    public var activePeripheral: CBPeripheral?
    public var characteristics = [String : CBCharacteristic]()
    public var data: NSMutableData?
    public var peripherals: [CBPeripheral] = [CBPeripheral]()
    public var RSSICompletionHandler: ((NSNumber?, Error?) -> ())?
    public var txChar: CBCharacteristic!
    public var rxChar: CBCharacteristic!
    // public var peripheralManager: CBPeripheralManager!
    
    override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        self.data = NSMutableData()
        
        // txChar = CBCharacteristic()
        // rxChar = CBCharacteristic
    }
    
    @objc func scanTimeout() {
        // print("[DEBUG] Scanning stopped")
        self.centralManager.stopScan()
        // print("[DEBUG] Peripherals: \(peripherals)")
    }
    
    // MARK: Public methods
    func startScanning(timeout: Double) -> Bool {
        if self.centralManager.state != .poweredOn {
            print("[BLE] Scan error (not powered on)")
            return false
        }
        
        print("[BLE] Scanning...")
        
        Timer.scheduledTimer(timeInterval: timeout, target: self, selector: #selector(BLE.scanTimeout), userInfo: nil, repeats: false)
        
        // let services: [CBUUID] = [CBUUID(string: serviceUUID)]
        self.centralManager.scanForPeripherals(withServices: nil, options: nil)
        return true
    }
    
    func connectToPeripheral(peripheral: CBPeripheral) -> Bool {
        
        if self.centralManager.state != .poweredOn {
            print("[ERROR] Couldn´t connect to peripheral")
            return false
        }
        
        //print("[DEBUG] Connecting to peripheral: \(peripheral.identifier.uuidString)")
        
        self.centralManager.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey : NSNumber(value: true)])
        
        return true
    }
    
    func disconnectFromPeripheral(peripheral: CBPeripheral) -> Bool {
        
        if self.centralManager.state != .poweredOn {
            
            print("[ERROR] Couldn´t disconnect from peripheral")
            return false
        }
        
        self.centralManager.cancelPeripheralConnection(peripheral)
        
        return true
    }

    func read() {
        self.activePeripheral?.readValue(for: rxChar)
    }

    func write(_ data: NSData) {
        self.activePeripheral?.writeValue(data as Data, for: txChar, type: .withoutResponse)
    }

    func enableNotifications(enable: Bool) {
        guard let char = self.characteristics[txCharacteristic] else { return }
        self.activePeripheral?.setNotifyValue(enable, for: char)
    }

    func readRSSI(completion: @escaping (_ RSSI: NSNumber?, _ error: Error?) -> ()) {
        self.RSSICompletionHandler = completion
        self.activePeripheral?.readRSSI()
    }
    
    // MARK: - CBCentralManager delegate methods
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            //print("[DEBUG] Central manager state: Unknown")
            break
            
        case .resetting:
            //print("[DEBUG] Central manager state: Resseting")
            break
            
        case .unsupported:
            //print("[DEBUG] Central manager state: Unsopported")
            break
            
        case .unauthorized:
            //print("[DEBUG] Central manager state: Unauthorized")
            break
            
        case .poweredOff:
            //print("[DEBUG] Central manager state: Powered off")
            break
            
        case .poweredOn:
            //print("[DEBUG] Central manager state: Powered on")
            break
        @unknown default:
            break
        }
        
        self.delegate?.bleDidUpdateState()
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
       // print("[CM] Found: \(peripheral.identifier.uuidString) (RSSI: \(RSSI))")
        
        print("[CM] Found: \(String(describing: peripheral.name)) (RSSI: \(RSSI))")
        
        // let index = peripherals.index { $0.identifier.uuidString == peripheral.identifier.uuidString }
        
        let index = peripherals.firstIndex { $0.name == peripheral.name }
        
        if let index = index {
            peripherals[index] = peripheral
        }
        else {
            peripherals.append(peripheral)
        }
        
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        
        //print("[CM] Error connecting to peripheral \(peripheral.identifier.uuidString) (\(error!.localizedDescription))")
        
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        //print("[DEBUG] Connected to peripheral \(peripheral.identifier.uuidString)")
        
        self.activePeripheral = peripheral
        
        self.activePeripheral?.delegate = self
        
        self.activePeripheral?.discoverServices([CBUUID(string: serviceUUID)])
        
        self.delegate?.bleDidConnectToPeripheral()
        
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        
        var text = "[DEBUG] Disconnected from peripheral: \(String(describing: peripheral.name))" // identifier.uuidString)"
        
        if error != nil {
            text += ". Error: \(error!.localizedDescription)"
        }
        
        // print(text)
        
        
        self.activePeripheral?.delegate = nil
        
        self.activePeripheral = nil
        
        self.characteristics.removeAll(keepingCapacity: false)
        
        self.delegate?.bleDidDisconenctFromPeripheral()
        
    }
    
    // MARK: CBPeripheral delegate
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        
        if error != nil {
            print("[ERROR] Error discovering services. \(error!.localizedDescription)")
            return
        }
        
        if let servicePeripheral = peripheral.services! as [CBService]? {
            for service in servicePeripheral {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
        
        //print("[DEBUG] Found services for peripheral: \(peripheral.identifier.uuidString)")

        for service in peripheral.services! {
            let theCharacteristics = [CBUUID(string: rxCharacteristic), CBUUID(string: txCharacteristic)]
            
            peripheral.discoverCharacteristics(theCharacteristics, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        if error != nil {
            print("[ERROR] Error discovering characteristics: \(error!.localizedDescription)")
            return
        }
        
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                self.characteristics[characteristic.uuid.uuidString] = characteristic
                
                // Tx:
                if characteristic.uuid == CBUUID(string: txCharacteristic) {
                    //print("TX Characteristics: \(characteristic.uuid)")
                    txChar = characteristic
                    //self.activePeripheral?.setNotifyValue(true, for: txChar)
                }
                // Rx:
                if characteristic.uuid == CBUUID(string: rxCharacteristic) {
                    //print("RX Characteristics: \(characteristic.uuid)")
                    rxChar = characteristic
                    //self.activePeripheral?.setNotifyValue(true, for: rxChar)
                }
            }
        }
        
        enableNotifications(enable: true)
        //print("[DEBUG] Found characteristics for peripheral: \(peripheral.identifier.uuidString)")
        
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let rxData = characteristic.value
        if let rxData = rxData {
            let numberOfBytes = rxData.count
            var rxByteArray = [UInt8](repeating: 0, count: numberOfBytes)
            (rxData as NSData).getBytes(&rxByteArray, length: numberOfBytes)
            // print(rxByteArray)
        }
        
        self.delegate?.bleDidReceiveData(data: characteristic.value as NSData?)
    }

    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        self.RSSICompletionHandler?(RSSI, error?.localizedDescription as! Error?)
        self.RSSICompletionHandler = nil
    }
    
    // MARK: - CBPeripheralManager delegate
    /*
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print("peripheralManagerDidUpdateState: \(peripheral.state)")
        if peripheral.state == .poweredOn {
            let dict = [CBAdvertisementDataLocalNameKey: "ConnLatencyTest"]
            // Generated with uuidgen
            let uuid = CBUUID(string: serviceUUID)
            let service = CBMutableService(type: uuid, primary: true)
            // value:nil makes it a dynamic-valued characteristic
            let latencyWrite = CBMutableCharacteristic(type: uuid, properties: .write, value: nil, permissions: CBAttributePermissions.writeable)
            let latencyRead = CBMutableCharacteristic(type: uuid, properties: .read, value: nil, permissions: CBAttributePermissions.readable)
            //var latencyCharacteristic = CBMutableCharacteristic(type: peripheralManager.latencyCharacteristicUuid(), properties: .read, value: nil, permissions: CBAttributePermissionsReadable)
            service.characteristics! = [latencyWrite, latencyRead]
            self.peripheralManager.add(service)
            self.peripheralManager.startAdvertising(dict)
            print("peripheralManager.startAdvertising [isAdvertising: \(self.peripheralManager.isAdvertising)]")
        }
    }
    */
}
