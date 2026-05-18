import SwiftUI

/// macOS 标准 Preferences 窗口。⌘, 唤起。
/// 把"调一次就不动"的设置项从主界面下沉到这里，让 Inspector 和 toolbar 保持极简。
struct PreferencesView: View {
    @Environment(PreferencesStore.self) private var prefs

    var body: some View {
        TabView {
            TimelineDisplayTab(prefs: prefs)
                .tabItem { Label("时间线", systemImage: "calendar.day.timeline.left") }
                .tag(0)
            OverlayInfoTab(prefs: prefs)
                .tabItem { Label("叠加信息", systemImage: "rectangle.badge.checkmark") }
                .tag(1)
            PreviewSourceTab(prefs: prefs)
                .tabItem { Label("预览", systemImage: "eye") }
                .tag(2)
        }
        .frame(minWidth: 480, minHeight: 380)
    }
}

// MARK: - 时间线显示

private struct TimelineDisplayTab: View {
    let prefs: PreferencesStore

    private var compactBinding: Binding<Bool> {
        Binding(get: { prefs.compactEmptyTime }, set: { prefs.compactEmptyTime = $0 })
    }
    private var thresholdBinding: Binding<Double> {
        Binding(get: { prefs.emptyGapThresholdMinutes }, set: { prefs.emptyGapThresholdMinutes = $0 })
    }

    var body: some View {
        Form {
            Section {
                Toggle("折叠空白时段", isOn: compactBinding)
                Text("两次拍摄间隔过长的「空白」会被压成窄缝，方便快速找到下一组照片。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("时间轴布局")
            }

            if prefs.compactEmptyTime {
                Section {
                    HStack {
                        Text("空白判定阈值")
                        Spacer()
                        Text(thresholdLabel).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Slider(value: thresholdBinding, in: 1...60, step: 1)
                    Text("两张照片间隔超过这个时长才算「空白」。越小折叠越激进。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var thresholdLabel: String {
        let v = prefs.emptyGapThresholdMinutes
        if v < 60 { return String(format: "%.0f 分钟", v) }
        return String(format: "%.1f 小时", v / 60)
    }
}

// MARK: - 预览叠加信息

private struct OverlayInfoTab: View {
    let prefs: PreviewOverlaySettings_ContainerProxy

    init(prefs: PreferencesStore) {
        self.prefs = PreviewOverlaySettings_ContainerProxy(prefs: prefs)
    }

    var body: some View {
        Form {
            Section {
                Toggle("在图片上显示参数", isOn: prefs.enabledBinding)
                Text("预览 / AB 对比时，浮在图片左上角的半透明信息卡。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if prefs.enabled {
                Section("显示哪些参数") {
                    Toggle("焦段", isOn: prefs.focal)
                    Toggle("光圈", isOn: prefs.aperture)
                    Toggle("快门", isOn: prefs.shutter)
                    Toggle("ISO", isOn: prefs.iso)
                    Toggle("机身", isOn: prefs.camera)
                    Toggle("镜头", isOn: prefs.lens)
                    Toggle("拍摄时间", isOn: prefs.date)
                    Toggle("文件名", isOn: prefs.filename)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// 为了让 OverlayInfoTab 的 toggles 都用 Binding，给 PreferencesStore 包一层 keyPath helper
private struct PreviewOverlaySettings_ContainerProxy {
    let prefs: PreferencesStore

    var enabled: Bool { prefs.overlay.enabled }

    var enabledBinding: Binding<Bool> {
        Binding(
            get: { prefs.overlay.enabled },
            set: { prefs.overlay.enabled = $0 }
        )
    }

    private func bind(_ keyPath: WritableKeyPath<PreviewOverlaySettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { prefs.overlay[keyPath: keyPath] },
            set: { prefs.overlay[keyPath: keyPath] = $0 }
        )
    }

    var focal: Binding<Bool>    { bind(\.showFocalLength) }
    var aperture: Binding<Bool> { bind(\.showAperture) }
    var shutter: Binding<Bool>  { bind(\.showShutter) }
    var iso: Binding<Bool>      { bind(\.showISO) }
    var camera: Binding<Bool>   { bind(\.showCamera) }
    var lens: Binding<Bool>     { bind(\.showLens) }
    var date: Binding<Bool>     { bind(\.showCaptureDate) }
    var filename: Binding<Bool> { bind(\.showFilename) }
}

// MARK: - 预览默认源

private struct PreviewSourceTab: View {
    let prefs: PreferencesStore

    private var singleBinding: Binding<Bool> {
        Binding(get: { prefs.singlePreviewPrefersRAW }, set: { prefs.singlePreviewPrefersRAW = $0 })
    }
    private var abBinding: Binding<Bool> {
        Binding(get: { prefs.abComparePrefersRAW }, set: { prefs.abComparePrefersRAW = $0 })
    }

    var body: some View {
        Form {
            Section {
                Picker("单图预览默认源", selection: singleBinding) {
                    Text("JPG").tag(false)
                    Text("RAW").tag(true)
                }
                .pickerStyle(.segmented)
                Text("打开单张图预览时默认显示哪种源。任何时候都可以按 J / R 切换。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("AB 对比默认源", selection: abBinding) {
                    Text("JPG").tag(false)
                    Text("RAW").tag(true)
                }
                .pickerStyle(.segmented)
                Text("AB 对比常用于 pixel-peep 比较画质，所以默认 RAW；可以改成 JPG 看相机出片差异。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
