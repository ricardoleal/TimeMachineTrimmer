cask "time-machine-trimmer" do
  version "1.0.0"
  sha256 "0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5"

  url "https://github.com/ricardoleal/TimeMachineTrimmer/releases/download/#{version}/TimeMachineTrimmer.dmg"
  name "TimeMachineTrimmer"
  desc "Trim old Time Machine backups, reclaim disk space"
  homepage "https://github.com/ricardoleal/TimeMachineTrimmer"

  app "TimeMachineTrimmer.app"

  caveats <<~EOS
    This app requires Full Disk Access.
    To grant it: System Settings → Privacy & Security → Full Disk Access → add TimeMachineTrimmer.

    The app is not signed with a Developer ID certificate.
    If macOS blocks it, open it via: System Settings → Privacy & Security → scroll to "Allow apps from…"
    Or right-click the app and select Open.
  EOS

  zap trash: [
    "~/Library/Application Scripts/com.ricardoleal.TimeMachineTrimmer",
    "~/Library/Containers/com.ricardoleal.TimeMachineTrimmer",
  ]
end
