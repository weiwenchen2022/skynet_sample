all : skynet/skynet
.PHONY : all update3rd

skynet/skynet : skynet/Makefile
	cd skynet && $(MAKE) linux

skynet/Makefile :
	git submodule update --init

update3rd :
	rm -rf skynet && git submodule update --init

.PHONY : clean cleanall

clean :
ifneq (,$(wildcard skynet/Makefile))
	cd skynet && $(MAKE) clean
endif

cleanall :
ifneq (,$(wildcard skynet/Makefile))
	cd skynet && $(MAKE) cleanall
endif
