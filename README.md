# NkSERVICE

# Introduction

NkSERVICE is an Erlang distributed application server, along with a scripting engine (based on [Luerl](https://github.com/rvirding/luerl) and a growing number of _Packages_ ready to use like RestServers, Kafka producers and consumers, Token management, et.

## Characteristics

* A powerful plugin mechanism, so that any package is made of a set of _plugins_ and a bit of custom login.
* New packages and modules can be added or removed at any moment. Its configuration can be changed at any moment.
* A powerful events mechanism with publish/subscribe semantics.
* A way to define service configuration and to develop server-side code using [Luerl](https://github.com/rvirding/luerl), a Lua-like language that is translated to Erlang on the fly.
* Designed from scratch to be highly scalable, having a very low latency.


## Packages and plugins

NkSERVICE features a sophisticated package system, based on plugins that allows a developer to modify the behavior of packages without having to modify its core, while having nearly zero overhead. Each plugin adds new _APIs_ and _callbacks_ or _hooks_, available to the service developer or other, higher level plugins.

Plugins have the concept _hierarchy_ and _dependency_. For example, if _pluginA_ implements callback _callback1_, we can define a new plugin _pluginB_ which depends on _pluginA_ and also implements _callback1_. Now, if the service (or other higher level plugin) happens to use this _callback1_, when it is called by NkSERVICE, the one that will be called first will ve the _pluginB_ version, and only if it returns `continue` or `{continue, Updated}` the version of `pluginA` would be called.

Any plugin can have any number of dependent plugins. NkSERVICE will ensure that versions of plugin callbacks on higher order plugins are called first, calling the next only in case it passes the call to the next plugin, possibly modifying the request. Eventually, the call will reach the default NkSERVICE's implementation of the callback (defined in [nkservice_callbacks.erl](src/nkservice_callbacks.erl) if all defined callbacks decide to continue, or no plugin has implemented this callback).

Plugin callbacks must be implemented in a module with the same name of the plugin, or a module called with the same name as the plugin plus _"_callbacks"_ (for example `my_plugin_callbacks.erl`). Plugin definitions must be implemented in a module with the same name of the plugin, plus _"_plugin"_

This callback chain behavior is implemented in Erlang and **compiled on the fly**, into a run-time generated service callback module. This way, any call to any plugin callback function is blazing fast, exactly the same as if it were hard-coded from the beginning. Calls to plugin callbacks not implemented in any plugin go directly to the default NkSERVICE implementation.

Each service can have **different set of plugins**, and it can **it be changed in real time** as any other service configuration value.



## Modules

Modules are scripts written in Luerl, that can start and configure any number of Packages, and then use them with any custom logic. The policy for launching this instances depends on the package. For example, the Rest package launches a module for each request, while the Kafka consumer group launches one for each topic & partition.


