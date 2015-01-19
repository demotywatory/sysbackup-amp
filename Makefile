SHELL = /bin/sh
PREFIX := /usr/local

install:
	install -d $(DESTDIR)/etc/cron.daily
	install etc/sysbackup-amp.cron.daily     $(DESTDIR)/etc/cron.daily/sysbackup-amp

	install -d $(DESTDIR)$(PREFIX)/sbin
	install src/sysbackup-amp.sh             $(DESTDIR)$(PREFIX)/bin/sysbackup-amp

	install -d $(DESTDIR)$(PREFIX)/share/man/man8
	install src/sysbackup-amp.8              $(DESTDIR)$(PREFIX)/share/man/man8/sysbackup-amp.8


uninstall:
	rm    $(DESTDIR)/etc/cron.daily/sysbackup-amp
	rm    $(DESTDIR)$(PREFIX)/bin/sysbackup-amp
	rm    $(DESTDIR)$(PREFIX)/share/man/man8/sysbackup-amp.8

