# GHOSTLINK Universal Bootstrap

This folder is the central update channel for the physical GHOSTKEY bootstrap.

A target PC uses the tiny GHOSTKEY Stage0 to fetch `ghostkey-manifest.json`,
select the compatible Bridge payload, verify SHA-256, then install/update the Bridge.

The Bridge keeps the user-facing command:

`DOWNLOAD GHOSTLINK`

Future stable Bridge fixes can therefore be published here once instead of rebuilding
the physical GHOSTKEY for every target PC.