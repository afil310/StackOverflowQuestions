//
//  QuestionsListController.swift
//  StackOverflow
//
//  Created by Andrey Filonov on 28/01/2019.
//  Copyright © 2019 Andrey Filonov. All rights reserved.
//

import UIKit
import WebKit

class QuestionsListController: UIViewController {

    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var tableView: UITableView!
    
    var response: Response?
    var tableDataSource: TableDataSource?
    var soRequest = StackoverflowRequest()
    let reachability = Reachability()
    let networkBar = NetworkBar()
    var activityIndicator: UIActivityIndicatorView!
    lazy var webViewController = WebViewController()
    var inetIsAvailable = true
    var requestPending = false
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupSubViews()
        tableView.separatorStyle = UITableViewCell.SeparatorStyle.none
        tableView.delegate = self
        if reachability?.connection.description != "No Connection" {
            loadData(url: soRequest.url)
        } else {
            inetIsAvailable = false
            requestPending = true
            showInetIsNotAvailableAlert(title: "Questions list")
        }
        
    }
    
    
    @objc func reachabilityChanged(note: Notification) {
        guard let reachability = note.object as? Reachability else {return}
        let greenColor = UIColor(red: 95/255, green: 186/255, blue: 125/255, alpha: 1.0)
        switch reachability.connection {
        case .wifi, .cellular:
            networkBar.hide(color: greenColor, message: "Internet is available")
            inetIsAvailable = true
            if requestPending {
                loadData(url: soRequest.url)
            }
        case .none:
            networkBar.show(color: .red, message: "Internet is not available")
            inetIsAvailable = false
        }
    }
    
    
    func setupSubViews() {
        setupNavigationBar()
        setupSearchBar()
        setupNetworkBar()
        activityIndicator = ActivityIndicator(view: view)
    }

    
    func setupNavigationBar() {
        let settingsBarButtonItem = UIBarButtonItem(image: UIImage(named: "Filter"),
                                                    style: .plain, target: self,
                                                    action: #selector(presentSettingsPage))
        navigationItem.rightBarButtonItem = settingsBarButtonItem
        navigationItem.title = "Questions"
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationController?.navigationBar.prefersLargeTitles = true
    }
    
    
    func setupSearchBar() {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchBar.delegate = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search Stackoverflow"
        searchController.hidesNavigationBarDuringPresentation = false
        definesPresentationContext = true
        navigationItem.searchController = searchController
    }
    
    
    @objc func presentSettingsPage() {
        let settingsStoryboard = UIStoryboard(name: "Settings", bundle: nil)
        guard let settingsPage = settingsStoryboard.instantiateViewController(withIdentifier: "SettingsTable") as? SettingsTableController else {return}
        let navigationController = UINavigationController(rootViewController: settingsPage)
        settingsPage.soRequest = soRequest
        settingsPage.quotaMax = response?.quota_max ?? 0
        settingsPage.quotaRemaining = response?.quota_remaining ?? 0
        settingsPage.delegate = self
        present(navigationController, animated: true)
    }
    
    
    func loadData(url: URL?) {
        UIView.animate(withDuration: 0.5, animations: {
            self.tableView.alpha = 0.0
        }, completion: { _ in
            self.activityIndicator.startAnimating()
        })
        let client = HTTPClient(url: url)
        client.httpClientDelegate = self
        client.request()
    }
    
    
    func setupNetworkBar() {
        NotificationCenter.default.addObserver(self, selector: #selector(reachabilityChanged(note:)), name: .reachabilityChanged, object: reachability)
        do {
            try reachability?.startNotifier()
        } catch {
            print("Error: could not start reachability notifier")
        }
        networkBar.translatesAutoresizingMaskIntoConstraints = false
        networkBar.isUserInteractionEnabled = false
        view.addSubview(networkBar)
        NSLayoutConstraint.activate([networkBar.widthAnchor.constraint(equalTo: view.widthAnchor),
                                     networkBar.topAnchor.constraint(equalTo: progressView.topAnchor)
            ])
    }
}


extension QuestionsListController: HTTPClientDelegate {
    func requestCompleted(response: Response?) {
        requestPending = false
        self.response = response
        tableDataSource = TableDataSource(response: response)
        tableView.dataSource = tableDataSource
        DispatchQueue.main.async {
            self.tableView.reloadData()
            self.activityIndicator.stopAnimating()
            UIView.animate(withDuration: 0.5, animations: {
                self.tableView.alpha = 1.0
            })
        }
    }
    
    
    func dataTaskProgress(progress: Float) {
        progressView.alpha = 1.0
        progressView.progress = progress
        if progress == 1.0 {
            UIView.animate(withDuration: 2.0, animations: {
                self.progressView.alpha = 0.0
            })
        }
    }
    
    
    func showInetIsNotAvailableAlert(title: String) {
        let alert = UIAlertController(title: title, message: "Internet connection is not available.\nReconnect and try again", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true)
    }
}


extension QuestionsListController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard response?.items.count != 0,
            let urlString = response?.items[indexPath.row].link else {return}
        guard let url = URL(string: urlString) else {
            print("Error converting \(urlString) to URL link")
            return
        }
        if inetIsAvailable {
            webViewController.activityIndicator.startAnimating()
            webViewController.webView.load(URLRequest(url: url))
            webViewController.webView.alpha = 0.0
            webViewController.navigationItem.largeTitleDisplayMode = .never
            navigationController?.pushViewController(webViewController, animated: true)
        } else {
            showInetIsNotAvailableAlert(title: "Question page")
        }
    }
}


extension QuestionsListController: SettingsTableDelegate {
    func settingsChanged(request: StackoverflowRequest) {
        soRequest = request
        if inetIsAvailable {
            loadData(url: soRequest.url)
        } else {
            requestPending = true
            showInetIsNotAvailableAlert(title: "Questions list")
        }
    }
}


extension QuestionsListController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let query = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines),
        soRequest.query != query else {return}
        soRequest.query = query
        if inetIsAvailable {
            loadData(url: soRequest.url)
            navigationController?.navigationBar.isHidden = false
        } else {
            showInetIsNotAvailableAlert(title: "Search")
            requestPending = true
        }
    }
    
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        // If the Cancel button clicked, then clear query and reload questions list
        if soRequest.query != "" {
            soRequest.query = ""
            if inetIsAvailable {
                loadData(url: soRequest.url)
            } else {
                requestPending = true
            }
        }
    }
}
