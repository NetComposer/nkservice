# NkSERVICE

# Overall picture

NkSERVICE is an Erlang framework to manage a complex set of services in a cluster.
It features a powerful plugin mechanism, so that any service is made of a set of _plugins_.

Services can be added and removed on the fly, and its configuration can be changed at any moment. Even new plugins can be added or removed at any moment.

In future versions, NkSERVICE will add the possibility to run 'external' services (using Docker containers), so that applications written in external languajes like Python or Java can use and extend the Erlang plugins.


## Plugins


NkSERVICE features a sophisticated plugin system, that allows a developer to modify the behaviour of services without having to modify its core, while having nearly zero overhead.

Each service must provide a _callback module_, that can implement a number of functions that NkSERVICE will call depending on various events. Plugins have the concept of _dependency_. For example, if pluginA_ implements callback _callback1_, we can define a new plugin _pluginB_ which depends on _pluginA_ and also implements _callback1_. Now, the _callback1_ version of _pluginB_ is the one that will be called first, and only if it returns `continue` or `{continue, list()}` the version of `pluginA` would be called.

Any plugin can have any number of dependant plugins. NkSERVICE will ensure that versions of plugin callbacks on higher order plugins are called first, calling the next only in case it returns `continue` or `{continue, NewArgs}`, and so on, eventualy reaching the default NkSERVICE's implementation of the callback (defined in [nkservice_callbacks.erl](src/nkservice_callbacks.erl) if all defined callbacks decide to continue, or no plugin has implemented this callback).

Of course plugins can offer new callbacks to be implemented (or not) at higher order plugins.

Plugin callbacks must be implemented in a module called with the same name as the plugin plus _"_callbacks"_ (for example `my_plugin_callbacks.erl`).

This callback chain behaviour is implemented in Erlang and **compiled on the fly**, into the generated runtime service callback module. This way, any call to any plugin callback function is blazing fast, exactly the same as if it were hard-coded from the beginning. Calls to plugin callbacks not implemented in any plugin go directly to the default NkSERVICE implementation.

Each service can have **different set of plugins**, and it can **it be changed in real time** as any other service configuration value.


