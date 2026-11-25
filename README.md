# OpenBar

An open bar for your VPN: [OpenConnect](https://www.infradead.org/openconnect/) in the macOS menu bar.
One click and you're in. No terminal, no `sudo`, no questions asked.

<p>
  <img src="docs/images/window.png" alt="The main window, connected" width="320">
  <img src="docs/images/panel.png" alt="The menu bar panel, connected" width="300">
</p>

> [!WARNING]
> This software was created irresponsibly, with Claude, and is shipped without any warranty.
> I decline all responsibility for whatever came out of it.
> It installs a helper that runs as root. Drink responsibly.

## Get in

```sh
brew install openconnect
```

```sh
./build.sh install
```

Open OpenBar, enter your server, user name and password, and click **Connect**.
The first round costs you an administrator password. The rest are on the house.

## Last call

Advanced tab, **Uninstall…**, then move the app to the Trash.

## Licence

LGPL 2.1, the same as OpenConnect, which does the actual work and is not to blame for any of this.
See [LICENSE](LICENSE).
