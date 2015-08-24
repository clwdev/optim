# optim
Optimize an entire folder for web.

What it does:
* Recursively optimizes images, videos and pdfs for the web.
* Uses a conservative amount of lossy compression.
* Safe to run repeatedly on the same folder (without degredation).

Saves:
* Bandwidth for the customers.
* Processing when down-sampling images via the CMS.
* Costly space in production.

Why?

The intention here is to be able to optimize web folders nightly, using rsync
and a spare machine. Most optimization scripts out there do not maintain some
kind of manifest, so there is no way of knowing what has been optimized. We 
wanted something that can be ran repeatedly, and only optimizes what is new
or updated. Also we wanted to optimize the big-hitting PDF and video files that
rarely see any optimization when uploaded by a client via a CMS.


Dependencies:
* OSX / GNU
* Ruby - https://www.ruby-lang.org
* Homebrew - http://brew.sh
* pv - http://www.ivarch.com/programs/pv.shtml

Optionals:
* pngout - http://www.jonof.id.au/kenutils

Utilizes:
* Image Optim - https://github.com/toy/image_optim
  (Including packed dependencies)
* Handbrake CLI - https://handbrake.fr/downloads2.php
* Ghostscript - http://www.ghostscript.com

In progress:
* Downscale excessively large images prior to normal optimization (4k+)
  This is so that things like ImageMagic have a chance to optimize in prod.
* Backup originals prior to replacement (especially for videos/pdf)
* Better handling of videos
* Better handling of PDFs
* Provide verbose/logging option
