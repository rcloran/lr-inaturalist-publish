# lr-inaturalist-publish

A Lightroom Classic plugin for publishing to iNaturalist and updating your
catalog with metadata from iNaturalist.

## Installation

1) Download the latest release zip file from [the releases page on
   GitHub](https://github.com/rcloran/lr-inaturalist-publish/releases/latest)
2) Extract the contents of the zip file.
   
   macOS: double click the zip file

   Windows: right click and select "Extract All..."
3) Move the lr-inaturalist-publish.lrplugin directory somewhere you would like
   the plugin to be stored.

   On macOS, the standard location for Lightroom Classic plugins is
   `~/Library/Application Support/Adobe/Lightroom/Modules` (that is, within
   the `Library` directory inside the user's home directory).

   On Windows, the standard location for Lightroom Classic plugins is
   `C:\Users\username\AppData\Roaming\Adobe\Lightroom\Modules`
4) In Lightroom, open the Plug-in Manager (`File` -> `Plug-in Manager`), and
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

#### Retrieving from iNaturalist

After initial setup you will be prompted to synchronize observations from
iNaturalist to your catalog. This will download all observation information and
try to find matching photos (based on criteria like time and location). Any
matches found will have metadata, such as the taxonomy and a link to the
observation, added to the photo.

<img src="docs/keywords.jpg" align="right" width="204" />

If you selected the option to update keywords from iNaturalist, keywords will
be created in a taxonomical hierarchy, and applied to your photo. The default
is to create keywords using the common name. If you unselect that option the
scientific name will be used instead. In either case, the alternate will be
used as a keyword synonym so that you can search by either.

If a photo can be uniquely associated to one photo within an observation, it
will also add photos into the "Observations" collection within the iNaturalist
publish service.

This initial download might take some time, but later synchronization
operations only retrieve changes since the last sync and should be much faster.
If you tend to take bursts of photos and keep the alternates in your catalog
the matching might not be very good; you can improve the likelihood of finding
matches (so that local metadata is set) by specifying a collection of photos in
which to restrict the search for matches. See [the wiki][1] for a more detailed
explanation.

The default configuration is to perform a new sync every time you publish.
This will retrieve any new information from iNaturalist (for example, new
identifications), and update the metadata. You can change this in the publish
service settings. You can also perform an ad-hoc sync, or a full
synchronization like the initial sync from the settings dialog.

[1]: https://github.com/rcloran/lr-inaturalist-publish/wiki/Synchronization

#### <div style="clear: both"></div>Adding to iNaturalist 

Once set up, add photos to the "Observations" collection like you would any
other collection in Lightroom. When you're ready to upload your images,
navigate to the collection and click the "Publish" button at the top. Your
images will be uploaded to iNaturalist, and observations will be created.

Keywords on your photos may be used as iNaturalist tags, species guesses, or
both, depending on how you configured the publish service.

If you have multiple photos that belong to one observation, you can group them
before publishing so that only one observation will be created. Select the
photos that should be grouped together, and use the `File` -> `Plug-in Extras`
-> `Group photos into observation` command to group them. You can assign a
keyboard shortcut to this menu item (I use cmd-O on my Mac) to make this
faster[^1].

You can also add photos to existing observations in the same way -- just group
the new photos with the photos already in the observation and publish.

You can delete photos from iNaturalist by removing them from the "Observations"
collection and publishing it again. If you remove all of the photos that belong
to an observation that observation will be deleted.

If you change a photo (for example change the develop settings) it will be
marked to be republished. When you publish, the photo will be uploaded again
(attaching it to the original observation), and the old version of the photo
will be deleted.

[^1]: On macOS you can create your own keyboard shortcut in your System Settings,
under Keyboard -> Keyboard Shortcuts -> App Shortcuts. Note that because
Lightroom places three spaces before the menu item, you need to put these into
the shortcut too.
