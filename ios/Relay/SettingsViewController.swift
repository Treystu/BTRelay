import UIKit
final class SettingsViewController: UIViewController {
  let secret = UITextField(); let rate = UITextField(); let burst = UITextField(); let cap = UITextField()
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Relay"
    view.backgroundColor = .systemBackground
    [secret,rate,burst,cap].forEach{ $0.borderStyle = .roundedRect }
    secret.placeholder = "Secret (hex)"; rate.placeholder = "Rate bytes/sec"; burst.placeholder = "Burst bytes"; cap.placeholder = "Monthly cap bytes"
    rate.keyboardType = .numberPad; burst.keyboardType = .numberPad; cap.keyboardType = .numberPad
    let stack = UIStackView(arrangedSubviews: [secret, rate, burst, cap, UIButton(type: .system)])
    stack.axis = .vertical; stack.spacing = 12
    view.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
    ])
    let btn = stack.arrangedSubviews.last as! UIButton
    btn.setTitle("Save", for: .normal)
    btn.addTarget(self, action: #selector(save), for: .touchUpInside)

    let cfg = Settings.load()
    secret.text = cfg.secretHex; rate.text = "\(cfg.rate)"; burst.text = "\(cfg.burst)"; cap.text = "\(cfg.cap)"
  }
  @objc func save(){
    let cfg = Settings(secretHex: secret.text ?? "", rate: Int64(rate.text ?? "") ?? 10_000, burst: Int64(burst.text ?? "") ?? 200_000, cap: Int64(cap.text ?? "") ?? 500*1024*1024)
    cfg.save()
    let alert = UIAlertController(title: "Saved", message: nil, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true)
  }
}
