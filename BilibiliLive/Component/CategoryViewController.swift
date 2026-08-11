//
//  CategoryViewController.swift
//  BilibiliLive
//
//  Created by yicheng on 2023/2/26.
//

import Foundation
import UIKit

class CategoryViewController: UIViewController, BLTabBarContentVCProtocol {
    struct CategoryDisplayModel {
        let title: String
        let contentVC: UIViewController
        var autoSelect: Bool? = true
    }

    var categories = [CategoryDisplayModel]()
    let contentView = UIView()
    weak var currentViewController: UIViewController?

    /// Categories used to be a 500pt left sidebar. Under the global rail that
    /// produced two stacked navigation columns and squeezed the content off
    /// the right edge, so they are a chip row now — same grammar as the index
    /// page, and it shares the rail's top baseline.
    private let chipBar = ChipBarView()
    private var didBuildChips = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Color.bg
        if !categories.isEmpty {
            initTypeCollectionView()
        }
    }

    func initTypeCollectionView() {
        if didBuildChips { return }
        didBuildChips = true

        view.addSubview(contentView)
        view.addSubview(chipBar)
        chipBar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.height.equalTo(DS.Chip.barHeight)
        }
        contentView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(chipBar.snp.bottom)
        }

        chipBar.setTitles(categories.map(\.title))
        chipBar.onSelect = { [weak self] index in self?.selectCategory(index) }
        chipBar.onFocusChange = { [weak self] index in
            guard let self, Settings.sideMenuAutoSelectChange else { return }
            guard categories[safe: index]?.autoSelect != false else { return }
            chipBar.setActive(index)
            selectCategory(index)
        }
        selectCategory(0)
    }

    private func selectCategory(_ index: Int) {
        guard let model = categories[safe: index] else { return }
        setViewController(vc: model.contentVC)
    }

    func setViewController(vc: UIViewController) {
        currentViewController?.willMove(toParent: nil)
        currentViewController?.view.removeFromSuperview()
        currentViewController?.removeFromParent()
        currentViewController = vc
        addChild(vc)
        contentView.addSubview(vc.view)
        vc.view.makeConstraintsToBindToSuperview()
        vc.didMove(toParent: self)
    }

    func reloadData() {
        (currentViewController as? BLTabBarContentVCProtocol)?.reloadData()
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
