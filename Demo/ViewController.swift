import UIKit
import SwiftScanKit

final class ViewController: UITableViewController {
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let configurations: [(title: String, color: UIColor, style: ScanAnimationStyle, tips: String)] = [
            ("扫一扫", .red, .default, ""), ("扫一扫", .red, .default, ""),
            ("微信扫一扫", .green, .default, "将二维码/条码放入框内，即可自动扫描"),
            ("支付宝扫一扫", .systemBlue, .grid, "放入框内，自动扫描")
        ]
        guard configurations.indices.contains(indexPath.row) else { return }
        let scanner = ScannerVC()
        let configuration = configurations[indexPath.row]
        let isModal = indexPath.row == 1
        scanner.title = configuration.title
        scanner.scannerColor = configuration.color
        scanner.animationStyle = configuration.style
        scanner.scannerTips = configuration.tips
        scanner.onScan = { [weak self] code in
            print(code)
            if isModal { self?.dismiss(animated: true) }
            else { self?.navigationController?.popViewController(animated: true) }
        }
        scanner.onError = { [weak scanner] error in
            guard (error as? ScannerError) != .sessionInterrupted else { return }
            guard let scanner, scanner.presentedViewController == nil else { return }
            let alert = UIAlertController(title: "无法扫描", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
            scanner.present(alert, animated: true)
        }
        let regionControl = UISegmentedControl(items: ["中间", "全屏"])
        regionControl.selectedSegmentIndex = 0
        regionControl.backgroundColor = .secondarySystemBackground
        regionControl.accessibilityLabel = "识别范围"
        regionControl.accessibilityIdentifier = "scanRegion"
        regionControl.addAction(UIAction { [weak scanner] action in
            guard let scanner, let control = action.sender as? UISegmentedControl else { return }
            scanner.scanRegion = control.selectedSegmentIndex == 0 ? .scanFrame : .fullScreen
            scanner.scannerTips = scanner.scanRegion == .fullScreen
                ? "将二维码或条形码置于屏幕内，即可自动识别"
                : configuration.tips
        }, for: .valueChanged)
        scanner.navigationItem.titleView = regionControl
        if isModal {
            scanner.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak scanner] _ in
                scanner?.dismiss(animated: true)
            })
            let navigation = UINavigationController(rootViewController: scanner)
            navigation.modalPresentationStyle = .fullScreen
            present(navigation, animated: true)
        } else {
            navigationController?.pushViewController(scanner, animated: true)
        }
    }
}
