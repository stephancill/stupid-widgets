import SwiftUI
import UIKit

struct WidgetElementID: Identifiable {
  let id = UUID()
  let object: JSObject
}

struct WidgetRenderer: View {
  let widget: ListWidgetModel
  var family: String = "medium"

  var body: some View {
    GeometryReader { geo in
      ZStack {
        background
        VStack(alignment: .leading, spacing: CGFloat(widget.spacing)) {
          ForEach(widget.children.map { WidgetElementID(object: $0) }) { item in
            child(item.object, parentLayout: .vertical)
          }
        }
        .padding(.top, CGFloat(widget.padding?.top ?? 12))
        .padding(.leading, CGFloat(widget.padding?.leading ?? 16))
        .padding(.bottom, CGFloat(widget.padding?.bottom ?? 12))
        .padding(.trailing, CGFloat(widget.padding?.trailing ?? 16))
      }
      .frame(width: geo.size.width, height: geo.size.height)
      .clipShape(RoundedRectangle(cornerRadius: family == "medium" ? 22 : 18))
    }
  }

  @ViewBuilder
  private var background: some View {
    if let gradient = widget.backgroundGradient {
      LinearGradient(
        gradient: swiftUIGradient(gradient),
        startPoint: .init(x: gradient.startPoint.x, y: gradient.startPoint.y),
        endPoint: .init(x: gradient.endPoint.x, y: gradient.endPoint.y)
      )
    } else if let image = widget.backgroundImage?.image {
      Image(uiImage: image).resizable().scaledToFill()
    } else {
      Color((widget.backgroundColor?.uiColor) ?? UIColor.systemBackground)
    }
  }

  private func swiftUIGradient(_ gradient: LinearGradientModel) -> Gradient {
    let colors = gradient.colors.map { Color($0.uiColor) }
    guard gradient.locations.count == colors.count else { return Gradient(colors: colors) }
    return Gradient(
      stops: zip(colors, gradient.locations).map { color, location in
        Gradient.Stop(color: color, location: location)
      })
  }

  func child(_ el: JSObject, parentLayout: WidgetLayout) -> AnyView {
    switch el {
    case let text as WidgetTextModel: return textView(text, fillsWidth: parentLayout == .vertical)
    case let date as WidgetDateModel: return dateView(date, fillsWidth: parentLayout == .vertical)
    case let image as WidgetImageModel:
      return imageView(image, fillsWidth: parentLayout == .vertical)
    case let spacer as WidgetSpacerModel:
      if spacer.length > 0 {
        return parentLayout == .horizontal
          ? AnyView(Spacer().frame(width: CGFloat(spacer.length)))
          : AnyView(Spacer().frame(height: CGFloat(spacer.length)))
      }
      return AnyView(Spacer(minLength: 0))
    case let stack as WidgetStackModel: return stackView(stack, parentLayout: parentLayout)
    default: return AnyView(EmptyView())
    }
  }

  func textView(_ text: WidgetTextModel, fillsWidth: Bool) -> AnyView {
    let view = Text(text.text)
      .font(text.font.map { Font($0.font) } ?? .body)
      .foregroundColor(text.textColor.map { Color($0.uiColor) } ?? .primary)
      .opacity(text.textOpacity)
      .lineLimit(text.lineLimit > 0 ? text.lineLimit : nil)
      .minimumScaleFactor(text.minimumScaleFactor)
      .multilineTextAlignment(
        text.alignment == .center ? .center : (text.alignment == .right ? .trailing : .leading)
      )
    guard fillsWidth else { return AnyView(view) }
    return AnyView(view.frame(maxWidth: .infinity, alignment: frameAlignment(text.alignment)))
  }

  func dateView(_ date: WidgetDateModel, fillsWidth: Bool) -> AnyView {
    let view = Text(dateLabel(date))
      .font(date.font.map { Font($0.font) } ?? .body)
      .foregroundColor(date.textColor.map { Color($0.uiColor) } ?? .primary)
      .opacity(date.textOpacity)
      .lineLimit(date.lineLimit > 0 ? date.lineLimit : nil)
      .minimumScaleFactor(date.minimumScaleFactor)
      .multilineTextAlignment(
        date.alignment == .center ? .center : (date.alignment == .right ? .trailing : .leading)
      )
    guard fillsWidth else { return AnyView(view) }
    return AnyView(view.frame(maxWidth: .infinity, alignment: frameAlignment(date.alignment)))
  }

  private func dateLabel(_ date: WidgetDateModel) -> String {
    if date.isRelative {
      let rel = RelativeDateTimeFormatter()
      rel.unitsStyle = .full
      return rel.localizedString(for: date.date, relativeTo: Date())
    }
    if date.isOffset {
      let comps = Calendar.current.dateComponents(
        [.hour, .minute, .second], from: Date(), to: date.date)
      return String(
        format: "%d:%02d:%02d", abs(comps.hour ?? 0), abs(comps.minute ?? 0), abs(comps.second ?? 0)
      )
    }
    if date.isTimer {
      let comps = Calendar.current.dateComponents(
        [.hour, .minute, .second], from: Date(), to: date.date)
      return String(
        format: "%02d:%02d:%02d", abs(comps.hour ?? 0), abs(comps.minute ?? 0),
        abs(comps.second ?? 0))
    }
    let formatter = DateFormatter()
    formatter.dateStyle = date.dateStyle
    formatter.timeStyle = date.timeStyle
    return formatter.string(from: date.date)
  }

  func imageView(_ image: WidgetImageModel, fillsWidth: Bool) -> AnyView {
    let view = Group {
      if let uiImage = image.image?.image {
        Image(uiImage: uiImage)
          .resizable()
          .aspectRatio(contentMode: image.contentMode == .fit ? .fit : .fill)
          .frame(
            width: image.imageSize.map { CGFloat($0.width) },
            height: image.imageSize.map { CGFloat($0.height) }
          )
          .opacity(image.imageOpacity)
          .cornerRadius(CGFloat(image.cornerRadius))
      } else {
        EmptyView()
      }
    }
    guard fillsWidth else { return AnyView(view) }
    return AnyView(view.frame(maxWidth: .infinity, alignment: frameAlignment(image.alignment)))
  }

  func stackView(_ stack: WidgetStackModel, parentLayout: WidgetLayout) -> AnyView {
    let spacing = CGFloat(stack.spacing)
    let view: AnyView
    if stack.layout == .horizontal {
      view = AnyView(
        HStack(spacing: spacing) {
          ForEach(stack.children.map { WidgetElementID(object: $0) }) { item in
            child(item.object, parentLayout: .horizontal)
          }
        })
    } else {
      view = AnyView(
        VStack(alignment: .leading, spacing: spacing) {
          ForEach(stack.children.map { WidgetElementID(object: $0) }) { item in
            child(item.object, parentLayout: .vertical)
          }
        })
    }
    guard parentLayout == .vertical else { return view }
    return AnyView(view.frame(maxWidth: .infinity, alignment: .leading))
  }

  private func frameAlignment(_ alignment: TextAlignment) -> Alignment {
    switch alignment {
    case .left: .leading
    case .center: .center
    case .right: .trailing
    }
  }
}
