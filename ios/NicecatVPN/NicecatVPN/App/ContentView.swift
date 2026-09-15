import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        ZStack {
            Color.niceBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                HeaderView()
                    .padding(.horizontal, 22)
                    .padding(.top, 26)
                    .frame(height: 112)

                Group {
                    switch model.currentPage {
                    case .home:
                        HomeView()
                    case .nodes:
                        NodesView()
                    }
                }
                .animation(.easeOut(duration: 0.18), value: model.currentPage)
            }
        }
        .preferredColorScheme(.dark)
        .alert("提示", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct HeaderView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        HStack(spacing: 14) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(AppConstants.appName)
                    .font(.system(size: 31, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(AppConstants.subtitle)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.niceMuted)
            }

            Spacer(minLength: 12)

            Text(model.phase.pillText)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(pillTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 112, height: 48)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(red: 0.125, green: 0.141, blue: 0.153))
                        .overlay(Capsule().stroke(Color(red: 0.25, green: 0.27, blue: 0.3), lineWidth: 1))
                )
        }
    }

    private var pillTextColor: Color {
        switch model.phase {
        case .connected:
            return Color.niceGreen
        case .testingDelay, .connecting:
            return Color.niceOrange
        default:
            return Color(red: 0.49, green: 0.83, blue: 0.99)
        }
    }
}

private struct HomeView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)

            VStack(spacing: 16) {
                Text(model.phase.centerText)
                    .font(.system(size: 33, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Button {
                    model.connectOrDisconnect()
                } label: {
                    Text(model.phase.buttonText)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color(red: 0.02, green: 0.08, blue: 0.05))
                        .frame(width: 154, height: 154)
                        .background(
                            Circle()
                                .fill(buttonColor)
                                .overlay(Circle().stroke(buttonColor.opacity(0.52), lineWidth: 11))
                                .shadow(color: buttonColor.opacity(0.18), radius: 12, x: 0, y: 4)
                        )
                }
                .buttonStyle(.plain)

                if model.phase == .connected {
                    HStack(spacing: 18) {
                        Text(model.downlinkText)
                        Text(model.uplinkText)
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                }
            }

            Spacer(minLength: 80)

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    model.currentPage = .nodes
                } label: {
                    Text("节点")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    model.currentPage = .nodes
                } label: {
                    SelectedNodeCard()
                }
                .buttonStyle(.plain)

                RouteModePicker()
                    .padding(.top, 18)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 26)
        }
    }

    private var buttonColor: Color {
        switch model.phase {
        case .connected:
            return Color.niceRed
        case .testingDelay, .connecting:
            return Color.niceOrange
        default:
            return Color.niceGreen
        }
    }
}

private struct SelectedNodeCard: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        HStack(spacing: 14) {
            FlagBadge(code: model.displayNode?.flagCode)
                .frame(width: 54, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedNodeName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(model.selectedNodeMeta)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.niceMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 10)

            DelayBadge(text: model.selectedDelayText, level: DelayBadge.level(for: model.displayNode, isAuto: model.selectedTag == AppConstants.autoTag && model.displayNode == nil))
        }
        .padding(.horizontal, 16)
        .frame(height: 78)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.043, green: 0.07, blue: 0.13))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.22, green: 0.29, blue: 0.41), lineWidth: 1))
        )
    }
}

private struct RouteModePicker: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        HStack(spacing: 18) {
            Text("代理规则")
            ForEach(RouteMode.allCases, id: \.rawValue) { mode in
                Button {
                    model.setRouteMode(mode)
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .stroke(mode == model.routeMode ? Color.niceBlue : Color.niceMuted, lineWidth: 4)
                                .frame(width: 24, height: 24)
                            if mode == model.routeMode {
                                Circle()
                                    .fill(Color.niceBlue)
                                    .frame(width: 12, height: 12)
                            }
                        }
                        Text(mode.title)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(maxWidth: .infinity)
    }
}

private struct NodesView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                NodeRow(node: nil, isAuto: true)
                ForEach(model.nodes) { node in
                    NodeRow(node: node, isAuto: false)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 26)
        }
        .refreshable {
            await model.refreshNodes()
        }
    }
}

private struct NodeRow: View {
    @EnvironmentObject private var model: AppViewModel
    let node: NodeProfile?
    let isAuto: Bool

    var body: some View {
        Button {
            if isAuto {
                model.selectAuto()
            } else if let node {
                model.select(node)
            }
        } label: {
            HStack(spacing: 18) {
                if isAuto {
                    AutoIcon()
                        .frame(width: 60, height: 46)
                } else {
                    FlagBadge(code: node?.flagCode)
                        .frame(width: 60, height: 46)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(isAuto ? "自动选择" : (node?.name ?? "节点"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(isAuto ? "自动测试并选择可用节点" : (node?.protocolTitle ?? "节点"))
                        .font(.system(size: 17))
                        .foregroundStyle(Color.niceMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 8)

                DelayBadge(
                    text: isAuto ? "AUTO" : (node?.delayText ?? "未测"),
                    level: DelayBadge.level(for: node, isAuto: isAuto)
                )
            }
            .padding(.horizontal, 16)
            .frame(height: 102)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
    }

    private var selected: Bool {
        isAuto ? model.selectedTag == AppConstants.autoTag : model.selectedTag == node?.tag
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(selected ? Color(red: 0.086, green: 0.133, blue: 0.192) : Color.niceCard)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.niceGreen : Color.niceStroke, lineWidth: selected ? 2 : 1)
            )
    }
}

private struct AutoIcon: View {
    var body: some View {
        Text("--")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Color.niceMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.047, green: 0.071, blue: 0.122))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.niceStroke, lineWidth: 1))
            )
    }
}

private struct FlagBadge: View {
    let code: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(red: 0.047, green: 0.071, blue: 0.122))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.niceStroke, lineWidth: 1))
            Text(FlagUtil.emoji(fromCode: code).isEmpty ? "--" : FlagUtil.emoji(fromCode: code))
                .font(.system(size: 31))
        }
        .clipped()
    }
}

struct DelayBadge: View {
    enum Level {
        case good
        case medium
        case bad
        case unknown
    }

    let text: String
    let level: Level

    var body: some View {
        Text(text)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 98, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(strokeColor, lineWidth: 1))
            )
    }

    static func level(for node: NodeProfile?, isAuto: Bool) -> Level {
        if isAuto {
            return .good
        }
        guard let node, let delay = node.delayMs else {
            return node?.delayTested == true ? .bad : .unknown
        }
        if delay <= 100 {
            return .good
        }
        if delay < 300 {
            return .medium
        }
        return .bad
    }

    private var textColor: Color {
        switch level {
        case .good: return Color(red: 0.73, green: 0.97, blue: 0.82)
        case .medium: return Color(red: 1.0, green: 0.95, blue: 0.78)
        case .bad: return Color(red: 1.0, green: 0.79, blue: 0.79)
        case .unknown: return Color.niceMuted
        }
    }

    private var backgroundColor: Color {
        switch level {
        case .good: return Color(red: 0.02, green: 0.22, blue: 0.14)
        case .medium: return Color(red: 0.31, green: 0.19, blue: 0.035)
        case .bad: return Color(red: 0.3, green: 0.08, blue: 0.08)
        case .unknown: return Color(red: 0.12, green: 0.16, blue: 0.23)
        }
    }

    private var strokeColor: Color {
        switch level {
        case .good: return Color(red: 0.0, green: 0.49, blue: 0.29)
        case .medium: return Color(red: 0.71, green: 0.33, blue: 0.035)
        case .bad: return Color(red: 0.73, green: 0.11, blue: 0.11)
        case .unknown: return Color(red: 0.2, green: 0.25, blue: 0.33)
        }
    }
}

private extension Color {
    static let niceBackground = Color(red: 0.043, green: 0.067, blue: 0.09)
    static let niceCard = Color(red: 0.071, green: 0.106, blue: 0.149)
    static let niceStroke = Color(red: 0.149, green: 0.212, blue: 0.29)
    static let niceMuted = Color(red: 0.624, green: 0.714, blue: 0.851)
    static let niceBlue = Color(red: 0.145, green: 0.388, blue: 0.922)
    static let niceGreen = Color(red: 0.133, green: 0.773, blue: 0.369)
    static let niceRed = Color(red: 0.937, green: 0.267, blue: 0.267)
    static let niceOrange = Color(red: 0.984, green: 0.749, blue: 0.141)
}
