import UIKit

/// The channels of a category, on the car's external display.
///
/// A shelf shows the first cards of a category; this list is the way into the
/// rest of it — the header of the shelf opens it. The external display is an
/// ordinary `UIWindowScene`, so it may show any view: this is a plain table,
/// which also copes with the thousands of rows a big playlist holds.
final class ChannelListViewController: UITableViewController {

    private let channels: [Channel]
    private let onSelect: (Channel) -> Void

    init(title: String, channels: [Channel], onSelect: @escaping (Channel) -> Void) {
        self.channels = channels
        self.onSelect = onSelect
        super.init(style: .plain)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("the list is built in code") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "channel")
        tableView.backgroundColor = UIColor(white: 0.09, alpha: 1)
        tableView.rowHeight = 52
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        channels.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "channel", for: indexPath)
        let channel = channels[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = channel.name
        content.secondaryText = channel.groupTitle
        content.textProperties.color = .white
        content.secondaryTextProperties.color = UIColor(white: 0.65, alpha: 1)
        cell.contentConfiguration = content
        cell.backgroundColor = UIColor(white: 0.13, alpha: 1)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let channel = channels[indexPath.row]
        dismiss(animated: true) { [onSelect] in onSelect(channel) }
    }
}
