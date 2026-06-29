# SPDX-FileCopyrightText: 2005-2011 TUBITAK/UEKAE, 2013-2017 Ikey Doherty, 2026-2027 Solzic0, LupuSzic0, LupuS
# SPDX-License-Identifier: GPL-2.0-or-later

import pisi.context as ctx


def switch_from_legacy(repo_url):
    if repo_url == "https://mirrors.rit.edu/lupus/packages/shannon/pisi-index.xml.xz":
        repo_url = "https://cdn.teknoanka.com/repo/shannon/pisi-index.xml.xz"
    elif (
        repo_url == "https://mirrors.rit.edu/lupus/packages/unstable/pisi-index.xml.xz"
    ):
        repo_url = "https://cdn.teknoanka.com/repo/unstable/pisi-index.xml.xz"

    return repo_url
