# SPDX-FileCopyrightText: 2005-2011 TUBITAK/UEKAE, 2013-2017 Ikey Doherty, 2026-2027 Solzic0, LupuSzic0, LupuS
# SPDX-License-Identifier: GPL-2.0-or-later

import optparse

from pisi import translate as _

import pisi.cli.command as command
import pisi.context as ctx
import pisi.api


class RebuildDb(command.Command, metaclass=command.autocommand):
    __doc__ = _(
        """Rebuild Databases

Usage: rebuilddb [ <package1> <package2> ... <packagen> ]

Rebuilds the pisi databases

If package specs are given, they should be the names of package
dirs under /var/lib/pisi
"""
    )

    def __init__(self, args):
        super(RebuildDb, self).__init__(args)

    name = ("rebuild-db", "rdb")

    def setup_options(self):
        group = optparse.OptionGroup(self.parser, _("rebuild-db options"))

        group.add_option(
            "-f",
            "--files",
            action="store_true",
            default=False,
            help=_("Rebuild files database"),
        )

        self.parser.add_option_group(group)

    def run(self):
        self.init(database=True)
        if ctx.ui.confirm(_("Rebuild pisi databases?")):
            pisi.api.rebuild_db(ctx.get_option("files"))
