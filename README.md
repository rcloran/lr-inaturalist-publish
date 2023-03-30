# lr-inaturalist-publish

A Lightroom Classic plugin for publishing to iNaturalist

## Installation

1) Copy the lr-inaturalist-publish.lrdevplugin directory somewhere you would
   like the plugin to be stored.

   On macOS, the standard location for Lightroom Classic plugins is
   `~/Library/Application Support/Adobe/Lightroom/Modules` (that is, within
   the `Library` directory inside the user's home directory).

   On Windows, the standard location for Lightroom Classic plugins is
   `C:\Users\username\AppData\Roaming\Adobe\Lightroom\Modules`

2) In Lightroom, open the Plug-in Manager (`File` -> `Plug-in Manager`), and
   add the plugin using the `Add` button near the bottom left of the window.

## Usage

Publish services are listed on the left panel in the Library module. After
installing the plugin, you should see a new iNaturalist service in the list
with a `Set Up...` link on the right of it -- click that!

Under the `iNaturalist Account` section, click `Log in`. Your browser will open
on iNaturalist and you will be asked to authorize this application's usage of
your account. Once you click Authorize, you may be prompted to allow opening
the link in Lightroom -- you should allow that. After returning to Lightroom
the dialog should update to indicate that you are logged in.

Change the export settings in whatever way you prefer, and click `Save`.

You may return to this set up later by right clicking the publish service and
choosing `Edit Settings...`

### Managing observations

Once set up, add photos to the Observations" collection like you would any
other collection in Lightroom. When you're ready to upload your images,
navigate to the collection and click the "Publish" button at the top. Your
images will be uploaded to iNaturalist, and observations will be created.

If you have multiple photos that belong to one observation, you can group them
before publishing so that only one observation will be created. Select the
photos that should be grouped together, and use the `File` -> `Plug-in Extras`
-> `Group photos into observation` command to group them. You can assign a
keyboard shortcut to this menu item (I use cmd-O on my Mac) to make this
faster[^1].

You can also add photos to existing observations in the same way -- just group
the new photos with the observation and publish.

You can delete photos from iNaturalist by removing them from the "Observations"
collection and publishing it again. If you remove all of the photos that belong
to an observation that observation will be deleted.

[^1]: On macOS you can create your own keyboard shortcut in your System Settings,
under Keyboard -> Keyboard Shortcuts -> App Shortcuts. Note that because
Lightroom places three spaces before the menu item, you need to put these into
the shortcut too.
