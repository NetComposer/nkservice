APP = nkservice
REBAR = rebar3
PRE1 = ERL_AFLAGS="-kernel net_ticktime 20"


.PHONY: rel stagedevrel package version all tree shell

all: version compile


version:
	@echo "$(shell git symbolic-ref HEAD 2> /dev/null | cut -b 12-)-$(shell git log --pretty=format:'%h, %ad' -1)" > $(APP).version


version_header: version
	@echo "-define(VERSION, <<\"$(shell cat $(APP).version)\">>)." > include/$(APP)_version.hrl


clean:
	$(REBAR) clean


rel:
	$(REBAR) release


compile:
	$(REBAR) compile


tests:
	$(REBAR) eunit


dialyzer:
	$(REBAR) dialyzer


xref:
	$(REBAR) xref


upgrade:
	$(REBAR) upgrade
	make tree


update:
	$(REBAR) update


tree:
	$(REBAR) tree | grep -v '=' | sed 's/ (.*//' > tree


tree-diff: tree
	git diff test -- tree


docs:
	$(REBAR) edoc


shell:
	$(REBAR) shell --config config/shell.config --name $(APP)@127.0.0.1 --setcookie nk --apps $(APP)


shell_env:
	$(REBAR) shell --config config/shell.config --name $(ERL_HOST) --setcookie nk --apps $(APP)


shell_a:
	$(REBAR) shell --config config/shell.config --name a@127.0.0.2 --setcookie nk --apps $(APP)

shell_b:
	$(REBAR) shell --config config/shell.config --name b@127.0.0.3 --setcookie nk --apps $(APP)

shell_c:
	$(REBAR) shell --config config/shell.config --name c@127.0.0.4 --setcookie nk --apps $(APP)
