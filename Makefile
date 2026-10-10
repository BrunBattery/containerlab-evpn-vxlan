.PHONY: clients deploy destroy inspect verify verify-underlay

clients:
	sudo docker build -t evpn-client:alpine3.23.6 lab/clients

deploy:
	bash scripts/deploy.sh

destroy:
	bash scripts/destroy.sh

inspect:
	sudo containerlab inspect --topo lab/evpn.clab.yml

verify:
	bash scripts/verify-overlay.sh

verify-underlay:
	bash scripts/verify.sh
