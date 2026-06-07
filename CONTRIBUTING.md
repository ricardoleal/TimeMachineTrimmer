# Contributing to TimeMachineTrimmer

Thank you for your interest in contributing! We welcome bug reports, feature requests, and pull requests.

## Getting Started

### Before You Start
- **Check existing issues** — Search [existing issues](https://github.com/ricardoleal/TimeMachineTrimmer/issues) to avoid duplicates
- **Discuss first** — [Open an issue](https://github.com/ricardoleal/TimeMachineTrimmer/issues/new) to discuss your idea before investing time in a PR

## How to Contribute

### 1. Fork the Repository
Click the **Fork** button at the top right of [ricardoleal/TimeMachineTrimmer](https://github.com/ricardoleal/TimeMachineTrimmer).

### 2. Clone Your Fork
```bash
git clone https://github.com/YOUR-USERNAME/TimeMachineTrimmer.git
cd TimeMachineTrimmer
```

### 3. Create a Feature Branch
```bash
git checkout -b feature/your-feature-name
```

Use descriptive branch names:
- `feature/add-export-option`
- `fix/crash-on-empty-backup`
- `docs/improve-readme`

### 4. Build and Test
Open the project in Xcode 26+ on macOS 26 (Tahoe):
```bash
open TimeMachineTrimmer.xcodeproj
```

> [!IMPORTANT]
> Change the signing team to your own in Xcode, otherwise entitlements may not persist.

### 5. Make Your Changes
- Follow the existing code style and conventions
- Keep commits atomic and well-documented
- Test thoroughly before submitting

### 6. Commit Your Changes
```bash
git add .
git commit -m "Brief description of changes"
```

### 7. Push to Your Fork
```bash
git push origin feature/your-feature-name
```

### 8. Open a Pull Request
1. Go to [ricardoleal/TimeMachineTrimmer](https://github.com/ricardoleal/TimeMachineTrimmer)
2. Click **"New Pull Request"**
3. Select your fork and branch
4. Fill out the PR template with details about your changes
5. Submit!

## Pull Request Guidelines

- **One feature per PR** — Keep PRs focused and manageable
- **Clear description** — Explain what and why, not just what
- **Reference issues** — Use "Closes #123" to link related issues
- **Test your changes** — Ensure everything works before submitting
- **Update documentation** — If your change affects user-facing behavior, update the README

## Code Style

- Follow Swift conventions and the existing codebase style
- Use meaningful variable and function names
- Add comments for complex logic
- Keep functions focused and single-purpose

## Questions?

Feel free to ask questions in the issue discussion or open a new issue. We're here to help!

---

**Thank you for contributing to TimeMachineTrimmer!** 🎉
