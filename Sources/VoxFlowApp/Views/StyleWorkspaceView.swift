import SwiftUI

struct StyleWorkspaceView: View {
    @ObservedObject var styleViewModel: StyleViewModel

    var body: some View {
        StyleView(viewModel: styleViewModel)
        .background(AppTheme.ColorToken.pageBackground)
    }
}
