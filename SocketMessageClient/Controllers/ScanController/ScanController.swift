//
//  ScanController.swift
//  SocketMessageClient
//
//  Created by Victor on 30.10.2019.
//  Copyright © 2019 Victor. All rights reserved.
//

import UIKit
import MMLanScan

class ScanController: UIViewController {
    enum State {
        case `default`
        case scanning
        case didScanned
    }
    
    enum PageType: String {
        case allDevices
        case activeDevices
    }
    
    //MARK: Outlets
    @IBOutlet fileprivate weak var tableView: UITableView!
    @IBOutlet fileprivate weak var progressView: UIProgressView!
    @IBOutlet fileprivate weak var segmentedControl: UISegmentedControl!
    private let serialQueue: DispatchQueue = DispatchQueue(label: "com.victor.socketmessageclient.scancontroller.serial")
    
    //MARK: Service
    lazy private var lanScanner: MMLANScanner = MMLANScanner(delegate: self)
    lazy private var multipleSocketConnect: MultipleSocketConnect = MultipleSocketConnect(firstPort: firstPort, endPort: lastPort)
    
    //MARK: Model
    private var currentPage: PageType = .allDevices {
        didSet {
            self.tableView.reloadData()
        }
    }
    
    private var devices: [PageType: [MDDevice]] = [PageType.allDevices: [], PageType.activeDevices: []]
    private var lanDevices: [LANDevice] = []
    private var state: State = .default
    private var firstPort: Int = 2000
    private var lastPort: Int = 2020
        
    //MARK: Life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startScan()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScan()
        multipleSocketConnect.disconnect()
    }
    
    //MARK: Setup
    private func setup() {
        let nib: UINib = UINib(nibName: DeviceCell.id, bundle: nil)
        self.tableView.register(nib, forCellReuseIdentifier: DeviceCell.id)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        
        multipleSocketConnect.delegate = self
        
        segmentedControl.addTarget(self, action: #selector(segmentedControlDidChangedValue(_:)), for: .valueChanged)
        
        showProgress(false)
        setupRefresh()
    }
}

//MARK: -UITableViewDelegate
extension ScanController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let device = self.devices[currentPage]![indexPath.row]
        if let socketStream = multipleSocketConnect.socketDevices[device] {
            let chatController = ChatController(chatType: .socketStream(socketStream: socketStream))
            self.navigationController?.pushViewController(chatController, animated: true)
        }
    }
}

//MARK: -UITableViewDataSource
extension ScanController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.devices[currentPage]!.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DeviceCell.id) as! DeviceCell
        cell.model = self.devices[currentPage]![indexPath.row]
        switch currentPage {
        case .activeDevices:
            cell.selectionStyle = .gray
        default:
            cell.selectionStyle = .none
        }
        return cell
    }
}

//MARK: -View
private extension ScanController {
    func setupRefresh() {
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(didRefresh), for: .valueChanged)
    }
    
    func showAlert(message: String) {
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        let ok = UIAlertAction(title: "Ok", style: .default, handler: nil)
        alertController.addAction(ok)
        self.present(alertController, animated: true, completion: nil)
    }
}

//MARK: -Actions
private extension ScanController {
    @objc func didRefresh() {
        switch state {
        case .default, .didScanned:
            reload()
        default:
            return
        }
    }
    
    @objc func segmentedControlDidChangedValue(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            self.currentPage = .allDevices
        case 1:
            self.currentPage = .activeDevices
        default:
            return
        }
    }
}

//MARK: -Scanner
extension ScanController: MMLANScannerDelegate {
    //MARK: MMLanScannerDelegate
    func lanScanDidFindNewDevice(_ device: MMDevice!) {
        DispatchQueue.main.async {
            self.lanDevices.append(device)
            let newDevice = MDDevice(ip: device.ipAddress, type: .notActive, computerName: device.hostname)
            self.addNewDevice(newDevice, to: .allDevices)
        }
    }
    
    func lanScanDidFinishScanning(with status: MMLanScannerStatus) {
        switch status {
        case MMLanScannerStatusFinished:
            finish(withMessage: "Scan did finished!")
        case MMLanScannerStatusCancelled:
            finish(withMessage: "Scanner was canceled!")
        default:
            return
        }
    }
    
    func lanScanProgressPinged(_ pingedHosts: Float, from overallHosts: Int) {
        self.progressView.progress = pingedHosts
    }
    
    func lanScanDidFailedToScan() {
        finish(withMessage: "Failed to scan :(")
    }
    
    //MARK: Scanning
    private func startScan() {
        self.lanScanner.start()
    }
    
    private func stopScan() {
        self.lanScanner.stop()
        self.state = .default
    }
    
    //MARK: Helping methods
    private func reload() {
        self.devices[currentPage] = []
        self.tableView.reloadData()
    }
    
    private func finish(withMessage message: String) {
        //showAlert(message: message)
        showProgress(false)
        self.state = .didScanned
        self.stopScan()
        for device in self.lanDevices {
            self.multipleSocketConnect.connectTo(device)
        }
    }
    
    private func showProgress(_ show: Bool) {
        self.progressView.isHidden = !show
    }
    
    private func addNewDevice(_ device: MDDevice, to page: PageType) {
        guard !(self.devices[page]?.contains(device) ?? false) else {return}
        var pageDevices = self.devices[page] ?? []
        pageDevices.append(device)
        self.devices[page] = pageDevices
        guard let count = self.devices[page]?.count, self.currentPage == page else {return}
        let indexPath = IndexPath(row: count - 1, section: 0)
        self.tableView.beginUpdates()
        self.tableView.insertRows(at: [indexPath], with: .bottom)
        self.tableView.endUpdates()
    }
}

//MARK: -MultipleSocketConnectDelegate
extension ScanController: MultipleSocketConnectDelegate {
    func multipleSocketConnect(_ multipleSocketConnect: MultipleSocketConnect, didAppendNewActiveDevice device: MDDevice) {
        self.addNewDevice(device, to: .activeDevices)
    }
}

