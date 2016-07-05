# NkSERVICE External API

## Core Commands

The currently supported External API commands as described here. See [External API](api_intro.md) for an introducition to the External API.

### Subscribe

Allows the connection to subscribe to specific events or event classes. The only mandatory field is `class`. Fields `obj`, `obj_id` and `type` defau"lt is `"*"`. The default `service` is the same that this connection belongs to.

See each plugin documentation to learn the supported event objects and types of each supported class.

Field|Type|Sample|Description
---|---|---|---
class|`string`|"media"|Class to subscribe to
obj|`string`|"session"|Object class belonging to the class
obj_id|`string`|"5179b729-367c-e79c-0399-38c9862f00d9"|Specific event to subscribe to
type|`string`|"hangup"|Specific event type to subscribe to

**Sample**

```js
{
	class: "core",
	cmd: "subscribe",
	data: {
		class: "media",
		obj: "session"
	}
}
```

This example would subscribe the connection to all specific sessions and event types for sessions beloging to the `media` class.





