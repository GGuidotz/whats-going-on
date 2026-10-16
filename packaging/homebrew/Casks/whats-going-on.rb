# frozen_string_literal: true

# Cask di What's Going On per il tap GGuidotz/homebrew-tap. Version e sha256 li aggiorna release.sh.
cask "whats-going-on" do
  version "0.6.0"
  sha256 "ae89d19949e26b9375410d79992c85baeada1281ddff1a45a2d90afa3d43dd7f"

  url "https://github.com/GGuidotz/whats-going-on/releases/download/v#{version}/WhatsGoingOn-#{version}.dmg"
  name "What's Going On"
  desc "Menu bar system monitor that tells you what's going on in one sentence"
  homepage "https://github.com/GGuidotz/whats-going-on"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "What's Going On.app"

  postflight do
    # L'app non è notarizzata (niente account Apple Developer): togliere la quarantena evita "Apri comunque".
    system_command "/usr/bin/xattr",
                   args:         ["-dr", "com.apple.quarantine", "#{appdir}/What's Going On.app"],
                   must_succeed: false
  end

  uninstall quit: "local.whatsgoingon.app"

  zap trash: "~/Library/Preferences/local.whatsgoingon.app.plist"

  caveats <<~EOS
    What's Going On lives in the menu bar. Alerts can go to Cocaine's island:
      brew install --cask mattiakart/tap/cocaine
    Cocaine shows them while you're at the Mac only with AI alerts > When > Also at the Mac;
    otherwise What's Going On also sends a macOS notification.
  EOS
end
