//
//  PIPKitEventDispatcher.swift
//  PIPKit
//
//  Created by Taeun Kim on 07/12/2018.
//

import Foundation
import UIKit

final class PIPKitEventDispatcher {
    
    var pipPosition: PIPPosition

    private var window: UIWindow? {
        rootViewController?.view.window
    }
    private weak var rootViewController: PIPKitViewController?
    private lazy var transitionGesture: UIPanGestureRecognizer = {
        UIPanGestureRecognizer(target: self, action: #selector(onTransition(_:)))
    }()
    private lazy var keyboardObserver: KeyboardObserver = {
        KeyboardObserver(delegate: self, adjustSafeAreaInset: true)
    }()
    private var isMoveFromKeyboard: Bool = false
    
    private var startOffset: CGPoint = .zero
    private var deviceNotificationObserver: NSObjectProtocol?
    private var windowSubviewsObservation: NSKeyValueObservation?
    
    deinit {
        keyboardObserver.deactivate()
        windowSubviewsObservation?.invalidate()
        deviceNotificationObserver.flatMap {
            NotificationCenter.default.removeObserver($0)
        }
    }
    
    init(rootViewController: PIPKitViewController) {
        self.rootViewController = rootViewController
        self.pipPosition = rootViewController.initialPosition
        
        commonInit()
        updateFrame()
        
        switch rootViewController.initialState {
        case .full:
            didEnterFullScreen()
        case .pip:
            didEnterPIP()
        }
    }
    
    func enterFullScreen() {
        UIView.animate(withDuration: 0.25, animations: { [weak self] in
            self?.updateFrame()
        }) { [weak self] (_) in
            self?.didEnterFullScreen()
        }
    }

    func enterPIP() {
        UIView.animate(withDuration: 0.25, animations: { [weak self] in
            self?.updateFrame()
        }) { [weak self] (_) in
            self?.didEnterPIP()
        }
    }
    
    func updateFrame() {
        guard let window = window,
            let rootViewController = rootViewController else {
                return
        }
        
        switch PIPKit.state {
        case .full:
            rootViewController.view.frame = window.bounds
        case .pip:
            updatePIPFrame()
        default:
            break
        }
        
        rootViewController.view.setNeedsLayout()
        rootViewController.view.layoutIfNeeded()
    }


    // MARK: - Private
    private func commonInit() {
        rootViewController?.view.addGestureRecognizer(transitionGesture)
        
        if let pipShadow = rootViewController?.pipShadow {
            rootViewController?.view.layer.shadowColor = pipShadow.color.cgColor
            rootViewController?.view.layer.shadowOpacity = pipShadow.opacity
            rootViewController?.view.layer.shadowOffset = pipShadow.offset
            rootViewController?.view.layer.shadowRadius = pipShadow.radius
        }
        
        if let pipCorner = rootViewController?.pipCorner {
            rootViewController.flatMap { pipCorner.apply(view: $0.view) }
        }
        
        deviceNotificationObserver = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                                                                            object: nil,
                                                                            queue: nil) { [weak self] (noti) in
                                                                                UIView.animate(withDuration: 0.15, animations: {
                                                                                    self?.updateFrame()
                                                                                }, completion:nil)
        }
        
        windowSubviewsObservation = window?.observe(\.subviews,
                                                     options: [.initial, .new],
                                                     changeHandler: { [weak self] window, _ in
            guard let rootViewController = self?.rootViewController else {
                return
            }
            
            window.bringSubviewToFront(rootViewController.view)
        })
    }
    
    private func didEnterFullScreen() {
        transitionGesture.isEnabled = false
        rootViewController?.didChangedState(.full)
        keyboardObserver.deactivate()
    }
    
    private func didEnterPIP() {
        transitionGesture.isEnabled = true
        rootViewController?.didChangedState(.pip)
        keyboardObserver.activate()
    }
    
    private func updatePIPFrame() {
        guard let window = window,
            let rootViewController = rootViewController else {
                return
        }
        
        var origin = CGPoint.zero
        let pipSize = rootViewController.pipSize
        let pipEdgeInsets = rootViewController.pipEdgeInsets
        var edgeInsets = UIEdgeInsets.zero
        
        if #available(iOS 11.0, *) {
            if rootViewController.insetsPIPFromSafeArea {
                edgeInsets = window.safeAreaInsets
            }
        }
        
        switch pipPosition {
        case .topLeft:
            origin.x = edgeInsets.left + pipEdgeInsets.left
            origin.y = edgeInsets.top + pipEdgeInsets.top
        case .middleLeft:
            origin.x = edgeInsets.left + pipEdgeInsets.left
            let vh = (window.frame.height - (edgeInsets.top + edgeInsets.bottom)) / 3.0
            origin.y = edgeInsets.top + (vh * 2.0) - ((vh + pipSize.height) / 2.0)
        case .bottomLeft:
            origin.x = edgeInsets.left + pipEdgeInsets.left
            origin.y = window.frame.height - edgeInsets.bottom - pipEdgeInsets.bottom - pipSize.height
        case .topRight:
            origin.x = window.frame.width - edgeInsets.right - pipEdgeInsets.right - pipSize.width
            origin.y = edgeInsets.top + pipEdgeInsets.top
        case .middleRight:
            origin.x = window.frame.width - edgeInsets.right - pipEdgeInsets.right - pipSize.width
            let vh = (window.frame.height - (edgeInsets.top + edgeInsets.bottom)) / 3.0
            origin.y = edgeInsets.top + (vh * 2.0) - ((vh + pipSize.height) / 2.0)
        case .bottomRight:
            origin.x = window.frame.width - edgeInsets.right - pipEdgeInsets.right - pipSize.width
            origin.y = window.frame.height - edgeInsets.bottom - pipEdgeInsets.bottom - pipSize.height
        }
        
        rootViewController.view.frame = CGRect(origin: origin, size: pipSize)
    }
    
    private func updatePIPPosition() {
        guard let window = window,
            let rootViewController = rootViewController else {
                return
        }
        
        let center = rootViewController.view.center
        var safeAreaInsets = UIEdgeInsets.zero
        
        if #available(iOS 11.0, *) {
            safeAreaInsets = window.safeAreaInsets
        }
        
        let vh = (window.frame.height - (safeAreaInsets.top + safeAreaInsets.bottom)) / 3.0
        
        switch center.y {
        case let y where y < safeAreaInsets.top + vh:
            pipPosition = center.x < window.frame.width / 2.0 ? .topLeft : .topRight
        case let y where y > window.frame.height - safeAreaInsets.bottom - vh:
            pipPosition = center.x < window.frame.width / 2.0 ? .bottomLeft : .bottomRight
        default:
            pipPosition = center.x < window.frame.width / 2.0 ? .middleLeft : .middleRight
        }
        
        rootViewController.didChangePosition(pipPosition)
    }
    
    private func updatePIPPositionAndMove(from keyboardEvent: Bool) {
        guard PIPKit.isPIP,
              let rootViewController = rootViewController else {
            return
        }
        
        let keyboardFrame = keyboardObserver.keyboardFrame
        var isNeedUpdate: Bool = false
        
        if keyboardObserver.isVisible {
            guard keyboardFrame.contains(rootViewController.view.frame) else {
                return
            }
            
            var frame = rootViewController.view.frame
            frame.origin.y -= keyboardObserver.visibleHeight
            rootViewController.view.frame = frame
            isNeedUpdate = true
            isMoveFromKeyboard = keyboardEvent
        } else if isMoveFromKeyboard {
            var frame = rootViewController.view.frame
            frame.origin.y += keyboardObserver.keyboardHeight
            rootViewController.view.frame = frame
            isNeedUpdate = true
            isMoveFromKeyboard = false
        }
        
        if isNeedUpdate {
            updatePIPPosition()
            UIView.animate(withDuration: 0.15) { [weak self] in
                self?.updatePIPFrame()
            }
        }
    }
    
    // MARK: - Action
    @objc
    private func onTransition(_ gesture: UIPanGestureRecognizer) {
        guard PIPKit.isPIP else {
            return
        }
        guard let window = window,
            let rootViewController = rootViewController else {
            return
        }
        
        switch gesture.state {
        case .began:
            isMoveFromKeyboard = false
            startOffset = rootViewController.view.center
        case .changed:
            let transition = gesture.translation(in: window)
            let pipSize = rootViewController.pipSize
            let pipEdgeInsets = rootViewController.pipEdgeInsets
            var edgeInsets = UIEdgeInsets.zero
            
            if #available(iOS 11.0, *) {
                if rootViewController.insetsPIPFromSafeArea {
                    edgeInsets = window.safeAreaInsets
                }
            }
            
            var offset = startOffset
            offset.x += transition.x
            offset.y += transition.y
            offset.x = max(edgeInsets.left + pipEdgeInsets.left + (pipSize.width / 2.0),
                           min(offset.x,
                               (window.frame.width - edgeInsets.right - pipEdgeInsets.right) - (pipSize.width / 2.0)))
            offset.y = max(edgeInsets.top + pipEdgeInsets.top + (pipSize.height / 2.0),
                           min(offset.y,
                               (window.frame.height - (edgeInsets.bottom) - pipEdgeInsets.bottom) - (pipSize.height / 2.0)))
            
            rootViewController.view.center = offset
        case .ended:
            updatePIPPositionAndMove(from: false)
        default:
            break
        }
    }
    
}

extension PIPKitEventDispatcher: KeyboardObserverDelegate {

    func keyboard(_ observer: KeyboardObserver, changed visibleHeight: CGFloat) {
        updatePIPPositionAndMove(from: true)
    }
    
}

extension PIPUsable where Self: UIViewController {
    
    func setupEventDispatcher() {
        pipEventDispatcher = PIPKitEventDispatcher(rootViewController: self)
    }
    
}
