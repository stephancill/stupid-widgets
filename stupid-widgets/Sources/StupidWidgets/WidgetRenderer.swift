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
        VStack(spacing: CGFloat(widget.spacing)) {
          ForEach(widget.children.map { WidgetElementID(object: $0) }) { item in
            child(item.object)
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
      }
      .frame(width: geo.size.width, height: geo.size.height)
      .clipShape(RoundedRectangle(cornerRadius: family == "medium" ? 22 : 18))
    }
  }

  @ViewBuilder
  private var background: some View {
    if let gradient = widget.backgroundGradient {
      LinearGradient(
        colors: gradient.colors.map { Color($0.uiColor) },
        startPoint: .init(x: gradient.startPoint.x, y: gradient.startPoint.y),
        endPoint: .init(x: gradient.endPoint.x, y: gradient.endPoint.y)
      )
    } else if let image = widget.backgroundImage?.image {
      Image(uiImage: image).resizable().scaledToFill()
    } else {
      Color((widget.backgroundColor?.uiColor) ?? UIColor.systemBackground)
    }
  }

  func child(_ el: JSObject) -> AnyView {
    switch el {
    case let text as WidgetTextModel: return AnyView(textView(text))
    case let date as WidgetDateModel: return AnyView(dateView(date))
    case let image as WidgetImageModel: return AnyView(imageView(image))
    case let spacer as WidgetSpacerModel:
      if spacer.length > 0 {
        return AnyView(Spacer().frame(height: CGFloat(spacer.length)))
      }
      return AnyView(Spacer(minLength: 0))
    case let stack as WidgetStackModel: return AnyView(stackView(stack))
    default: return AnyView(EmptyView())
    }
  }

  @ViewBuilder
  func textView(_ text: WidgetTextModel) -> some View {
    Text(text.text)
      .font(text.font.map { Font($0.font) } ?? .body)
      .foregroundColor(text.textColor.map { Color($0.uiColor) } ?? .primary)
      .opacity(text.textOpacity)
      .lineLimit(text.lineLimit > 0 ? text.lineLimit : nil)
      .minimumScaleFactor(text.minimumScaleFactor)
      .multilineTextAlignment(
        text.alignment == .center ? .center : (text.alignment == .right ? .trailing : .leading)
      )
      .frame(
        maxWidth: .infinity,
        alignment: text.alignment == .center
          ? .center : (text.alignment == .right ? .trailing : .leading))
  }

  @ViewBuilder
  func dateView(_ date: WidgetDateModel) -> some View {
    Text(dateLabel(date))
      .font(date.font.map { Font($0.font) } ?? .body)
      .foregroundColor(date.textColor.map { Color($0.uiColor) } ?? .primary)
      .opacity(date.textOpacity)
      .lineLimit(date.lineLimit > 0 ? date.lineLimit : nil)
      .multilineTextAlignment(
        date.alignment == .center ? .center : (date.alignment == .right ? .trailing : .leading)
      )
      .frame(
        maxWidth: .infinity,
        alignment: date.alignment == .center
          ? .center : (date.alignment == .right ? .trailing : .leading))
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

  @ViewBuilder
  func imageView(_ image: WidgetImageModel) -> some View {
    Group {
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
    .frame(
      maxWidth: .infinity,
      alignment: image.alignment == .center
        ? .center : (image.alignment == .right ? .trailing : .leading))
  }

  @ViewBuilder
  func stackView(_ stack: WidgetStackModel) -> some View {
    let spacing = CGFloat(stack.spacing)
    let content = Group {
      ForEach(stack.children.map { WidgetElementID(object: $0) }) { item in
        child(item.object)
      }
    }
    if stack.layout == .horizontal {
      HStack(spacing: spacing) { content }
    } else {
      VStack(spacing: spacing) { content }
    }
  }
}
