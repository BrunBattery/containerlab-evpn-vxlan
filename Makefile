.PHONY: deploy destroy inspect verify

deploy:
	bash scripts/deploy.sh

destroy:
	bash scripts/destroy.sh

inspect:
	sudo containerlab inspect --topo lab/evpn.clab.yml

verify:
	bash scripts/verify.sh
