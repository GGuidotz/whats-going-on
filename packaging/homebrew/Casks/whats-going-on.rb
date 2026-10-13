# frozen_string_literal: true

# Cask di What's Going On per il tap GGuidotz/homebrew-tap. Version e sha256 li aggiorna release.sh.
cask "whats-going-on" do
  version "0.4.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

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
    What's Going On vive nella barra dei menu. Gli avvisi arrivano nell'isola di Cocaine se è aperto:
      brew install --cask mattiakart/tap/cocaine
  EOS
end
