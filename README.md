# ReadAperture.playground

As Aperture started to fail in my Mac, I finally had to migrate all may images to another application. 
I picked Capture One as it promised to be able to preserve two things that are essential to me: 

- Metadata and tags
- Crops 
 
It turned out that the Capture One (20 and 21) import blew up the majority of my crops. 

This playground started as effort to analyze what went wrong (and how often). 
FixApertureImport.xcodeproj only exists to import the SPM package 'GRDB' that is used for SQLITE access.

As Capture One uses also an SQLITE backing store, I expanded it to compare the created Capture One versions and crops.
In the end it was possible to correct them.

The summary is that Capture One uses an odd coordinate system to store crops 

- (centerX, centerY, width, height) in landscape
- (centerX, imageHeight - centerY, HEIGHT, WIDTH) for portrait.

When importing an portrait (=rotated) Aperture version Capture One 
- miscalculates the y coordinate 
- scales the crop size with the miscalculated coordinate to fit in the image, so most crops end up as zero size (which gets handled in the UI as "no crop at all"). Clipping is also done in the playground - just in case the slightly different image sizes cause a crop to go out of image bounds - but the code is not very sophisticated. 

This playground corrects my C1 21 database. 
It is completely based on reverse engineering and should only be applied to a copy of a database - USE AT YOUR OWN RISK.


