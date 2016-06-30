# NkSERVICE

# Overall picture

NkSERVICE is an Erlang framework to manage a complex set of services in a cluster. It features:
* A powerful plugin mechanism, so that any service is made of a set of _plugins_ and a bit of custom login.
* New plugins can be added or removed at any moment. Its configuration can be changed at any moment. 
* A flexible and easy to use External API, that any service can expose over tcp, tls, ws or wss. Each started plugins in the service can _add_ commands, making them available for use from outside the cluster.
* A powerful events mechanism with publish/subscribe semantics.
* A way to define service configuration and to develop server-side code using [Luerl](https://github.com/rvirding/luerl), a Lua-like language that is translated to Erlang on the fly.
* Designed from scratch to be highly scalable, having a very low latency.

The vision around NkSERVICE is using Erlang to develop plugins that are offered to services. Service specific login can run inside the cluster (using Luerl or Erlang) or out of the cluster using the External API.


## Plugins

NkSERVICE features a sophisticated plugin system, that allows a developer to modify the behavior of services without having to modify its core, while having nearly zero overhead. Each plugin adds new _APIs_ and _callbacks_ or _hooks_, available to the service developer or other, higher level plugins.

Plugins have the concept _hierarchy_ and _dependency_. For example, if _pluginA_ implements callback _callback1_, we can define a new plugin _pluginB_ which depends on _pluginA_ and also implements _callback1_. Now, if the service (or other higher level plugin) happens to use this _callback1_, when it is called by NkSERVICE, the one that will be called first will ve the _pluginB_ version, and only if it returns `continue` or `{continue, Updated}` the version of `pluginA` would be called.

Any plugin can have any number of dependent plugins. NkSERVICE will ensure that versions of plugin callbacks on higher order plugins are called first, calling the next only in case it passes the call to the next plugin, possibly modifying the request. Eventually, the call will reach the default NkSERVICE's implementation of the callback (defined in [nkservice_callbacks.erl](src/nkservice_callbacks.erl) if all defined callbacks decide to continue, or no plugin has implemented this callback).

Plugin callbacks must be implemented in a module with the same name of the plugin, or a module called with the same name as the plugin plus _"_callbacks"_ (for example `my_plugin_callbacks.erl`).

This callback chain behavior is implemented in Erlang and **compiled on the fly**, into a run-time generated service callback module. This way, any call to any plugin callback function is blazing fast, exactly the same as if it were hard-coded from the beginning. Calls to plugin callbacks not implemented in any plugin go directly to the default NkSERVICE implementation.

Each service can have **different set of plugins**, and it can **it be changed in real time** as any other service configuration value.



## Services

New services can be defined in NkSERVICE's global configuration, or programatically using Erlang or the external API. Also, any file with extension .ncl in the directory _services_ will be loaded during boot, and, if they contain valid service definitions (written in Luerl), will be started.

Services can also be started using the External API, but you must authenticate yourself using the user and password defined in NkSERVICE's global configuration. You can this way inject the Luerl service definition and logic, or subscribe to all the callback functions you are interested in implement.

When defining a service, you can set an administrator users and password. Special commands, like subscribing to callback functions, can only be performed by the administrator of the service. 



## External API

NkSERVICE offers a flexible, easy to use protocol suitable for developing both client-side applications (supporting hundreds of thousands of connections) and server-side applications, where an external application written in any language can start any number of channels to a service, and receive incoming tasks and messages, that are load-balanced over all started channels.

See the [external API introduction](doc/api_intro.md) for a description of the protocol, and [external API commands](doc/api_commands.erl) for currently implemented commands and events in NkSERVICE. Any activated plugin for a service can add new commands and events, of modify the behavior of current ones.

