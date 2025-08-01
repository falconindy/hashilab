OUTS = \
	keepalived.nomad0.conf \
	keepalived.nomad1.conf \
	keepalived.nomad2.conf

keepalived.nomad0.conf: keepalived.conf.tmpl
	KEEPALIVED_STATE=MASTER \
	KEEPALIVED_PRIO=100 \
		envsubst <$^ >$@

keepalived.nomad1.conf: keepalived.conf.tmpl
	KEEPALIVED_STATE=BACKUP \
	KEEPALIVED_PRIO=81 \
		envsubst <$^ >$@

keepalived.nomad2.conf: keepalived.conf.tmpl
	KEEPALIVED_STATE=BACKUP \
	KEEPALIVED_PRIO=82 \
		envsubst <$^ >$@

clean:
	$(RM) $(OUTS)

all: $(OUTS)
