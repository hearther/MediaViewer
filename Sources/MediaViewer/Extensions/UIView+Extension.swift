//
//  UIView+Extension.swift
//  
//
//  Created by Yusaku Nishi on 2023/02/25.
//

import UIKit

extension UIView {
    
    /// Update the anchor point while keeping its position fixed.
    /// - Parameter newAnchorPoint: The new anchor point.
    func updateAnchorPointWithoutMoving(_ newAnchorPoint: CGPoint) {
        if #available(iOS 16.0, *) {
            frame.origin.x += (newAnchorPoint.x - anchorPoint.x) * frame.width
            frame.origin.y += (newAnchorPoint.y - anchorPoint.y) * frame.height
            anchorPoint = newAnchorPoint
        } else {
            // Fallback on earlier versions
            // iOS 16 以下的版本
            let oldOrigin = frame.origin
            layer.anchorPoint = newAnchorPoint
            let newOrigin = layer.frame.origin
            
            // 計算 offset 並更新位置
            let offsetX = newOrigin.x - oldOrigin.x
            let offsetY = newOrigin.y - oldOrigin.y
            frame = frame.offsetBy(dx: -offsetX, dy: -offsetY)
        }                
    }
    
    func firstSubview<View>(ofType type: View.Type) -> View? where View: UIView {
        for subview in subviews {
            if let view = subview as? View {
                return view
            }
            if let view = subview.firstSubview(ofType: View.self) {
                return view
            }
        }
        return nil
    }
}
