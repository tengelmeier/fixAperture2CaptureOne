import GRDB
import Foundation

let pathPrefix = "/Volumes/External/Pictures"
let apPath = pathPrefix + "/Aperture Libraries/Aperture Library.aplibrary/Database/apdb/Library.apdb"
// let c1Path = "/Volumes/External/Pictures/C1 Crop Samples/CropSamples.cocatalog/CropSamples.cocatalogdb"
let c1Path = pathPrefix + "/Capture One Catalog.cocatalog/Capture One Catalog.cocatalogdb"
let writeChanges = false // set to true to write out the result

// optional filter. Helps reversing the transformation with a limited image set
let filesToFilter = [String]() // ["_DSC4222.NEF", "_DSC4290.NEF", "_DSC4385.NEF", "_DSC4418.NEF"]

func toDouble( _ value: Any? ) -> Double {
    if let f = value as? Double {
        return f
    } else if let nr = value as? NSNumber {
        return nr.doubleValue
    }

    print( "Can't convert \(value)")
    return 0
}

func equalSize( _ s1: CGSize, _ s2: CGSize, epsilon: CGFloat ) -> Bool {
    return ( abs( s1.width - s2.width ) < epsilon) && (abs( s1.height - s2.height ) < epsilon)
}

class CropVersion  : CustomStringConvertible {
    let name : String
    let imageSize: CGSize
    let rotation: Double
    let crop: CGRect

    var rotatedCrop : CGRect {
        rotateRect( crop, by: Int( rotation ), imageSize: imageSize)
    }

    private func rotateRect(_ rect: CGRect, by degrees:Int, imageSize: CGSize ) -> CGRect {
        let rotation = (degrees % 360) / 90

        switch rotation {
        case 1:
            return CGRect( x: rect.minY, y: imageSize.width - rect.maxX, width: rect.height, height: rect.width)
        case 2:
            return CGRect( x: imageSize.width - rect.maxX, y: imageSize.height - rect.maxY, width:rect.width, height: rect.height )
        case 3:
            return CGRect( x: imageSize.height - rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
        default:
            return rect
        }
    }

    lazy var cropForCaptureOne : CGRect = {
        if isPortrait( Int( rotation ) ) {
            return CGRect( origin: CGPoint( x: crop.origin.x + (crop.size.width / 2.0),
                                            y: imageSize.height - crop.minY - (crop.size.height / 2.0) ),
                           size:crop.size )
        }
        return crop.offsetBy(dx: crop.size.width / 2.0, dy: crop.size.height / 2.0 )
    }()

    var description : String {
        var s = "\(name) \(imageSize) : \(crop)"
        if rotation != 0 { s = s.appending( " x \(rotation)" ) }
        return s
    }

    init( _ name: String, size: CGSize, crop:CGRect, rotation:Double ) {
        self.name = name
        self.crop = crop
        self.rotation = rotation
        self.imageSize = size
    }
}

func isPortrait( _ angle: Int ) -> Bool {
    return ( angle % 90) % 2 == 1
}

struct VersionCorrection {
    let pk: Int
    let crop : CGRect
    let imageSize : CGSize
    let rotation: Double

    // C1 imports images sometimes slightly smaller than Aperture.
    // This means the crops may not be completely in the image and need to be inset

    var clippedCrop : CGRect {
        if isPortrait( Int( rotation ) ) {
            // I hate working with the {center,size} coordiante system.
            // Transform to {origin, size}
            var c = crop.offsetBy(dx: -(crop.size.width / 2.0), dy: -(crop.size.height / 2.0)) // TODO: Test if dx <=> width

            // Find the bigger outlier. as it'ts only out of bounds if negative, use min
            var dx = min( c.minX, imageSize.height - c.maxX )
            var dy = min( c.minY, imageSize.width - c.maxY )

            // square? Adjust the inset so the crop keeps square
            if c.size.width.distance( to: c.size.height ) < 1.0 {
                dx = min( dx, dy )
                dy = min( dx, dy )
            }

            // now we have to crop:
            if dx < 0 {
                c.size.width -= ( 2 * dx )
            }
            if dy < 0 {
                c.size.height -= ( 2 * dy )
            }

            // and transform back
            let clipped = c.offsetBy(dx: (crop.size.width / 2.0), dy: (crop.size.height / 2.0))
            if clipped != crop {
                print( "Clipped \(crop) in \(imageSize) -> \(clipped)")
            }
            return clipped
        }
        return crop
    }
}

var apVersions = [String:[CropVersion]]()
var rotatedVersions = 0

print( "**** Reading Aperture versions" )

let apQueue = try DatabaseQueue(path: apPath )
try apQueue.read {
    db in
    let rows = try Row.fetchAll(db, sql: "select data, fileName, rotation, masterWidth, masterHeight from rkimageadjustment inner join RKVersion on RKVersion.uuid = rkimageadjustment.versionUuid where rkimageadjustment.name = \"RKCropOperation\"")

    rows.forEach {
        row in
        // let uuid: String = row["versionUuid"]
        let data: Data = row["data"]

        do {

            if let obj = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? [String:Any] {
                let keys = obj["inputKeys"]! as! [String:Any]

                let fname = row["fileName"] as String
                if !filesToFilter.isEmpty, !filesToFilter.contains( fname ) {
                    return
                }

                let rotation = toDouble( row["rotation"] )

                let size = CGSize( width:  row["masterWidth"] as Int,
                                   height: row["masterHeight"]as Int)


                let rect = CGRect(x: toDouble( keys["inputXOrigin"] ),
                                  y: toDouble( keys["inputYOrigin"] ),
                                  width: toDouble( keys["inputWidth"] ),
                                  height: toDouble( keys["inputHeight"] ) )

                let version = CropVersion( fname, size:size, crop: rect, rotation: rotation)

                if version.crop.size != .zero,
                   version.crop.size != size, // filter invalid crops and landscape (landscape import worked)
                   version.rotation != 0 {
                    var fileVersions = apVersions[fname] ?? [version]
                    if let v1 = fileVersions.first,
                       v1.crop != version.crop {
                        fileVersions.append( version )
                    }
                    apVersions[fname] = fileVersions

                    if rotation != 0 {
                        rotatedVersions += 1
                    }

                    print( version, version.cropForCaptureOne )
                }
            }
        } catch {
            print ("\(error)")
        }
    }
}

// Determine how many versions may be ambiguous and can't be automatically corrected
let multiVersions = apVersions.values.filter{ $0.count > 1 }.filter{ $0[0].cropForCaptureOne.origin.x == $0[1].cropForCaptureOne.origin.x }.map(){ ($0.first!.name, $0.map{ $0.cropForCaptureOne } ) }
print( multiVersions )

// print( rotatedVersions )

// Preprocessing stats
var matches = 0
var non_matches = 0
var missing = 0

var correctionsToApply = [VersionCorrection]()

print( "**** Locating corresponding Capture One versions" )

let c1Queue = try DatabaseQueue(path: c1Path )

do {
    try c1Queue.read {
        db in
        let rows = try Row.fetchAll(db, sql: "select z_pk, zcrop, zvariant, zrotation from zvariantlayer where zcrop != 0")

        rows.forEach {
            row in
            let crop: String = row["zcrop"]
            if crop != "0.000000;0.000000;0.000000;0.000000" {
                let variant : Int = row["zvariant"]
                let variant_pk : Int = row["z_pk"]
                let rotation  = row["zrotation"] as? Double ?? 0

                do {
                    if let image = try Row.fetchOne( db, sql: "select zimage.zimagefilename, zimage.zwidth, zimage.zheight, zvariant.zadjustmentlayer, zvariant.zcombinedsettings from zvariant inner join zimage on zimage.z_pk = zvariant.zimage where zvariant.z_pk = \(variant)" ) {

                        let name : String = image["zimagefilename"]
                        let imageSize = CGSize( width: image["zwidth"] as Int, height: image["zheight"] as Int )
                        let adjustmentLayer = image["zadjustmentlayer"] as Int
                        let combinedLayer = image["zcombinedsettings"] as Int


                        var skipProcessing = (adjustmentLayer != variant_pk) && (combinedLayer != variant_pk)

                        if !skipProcessing,
                           let someVersions = apVersions[name],
                           let anyVersion = someVersions.first,
                           anyVersion.rotation != 0.0 {

                            // print( crop )
                            let coordinates = crop.components(separatedBy: ";").map{ Double( $0 ) ?? 0.0 }
                            let coOrigin = CGPoint( x: coordinates[0], y: coordinates[1] )
                            // let coSize = CGSize( width: coordinates[2], height: coordinates[3])
                            // "Unrotate" the size:
                            let coSize = CGSize( width: coordinates[3], height: coordinates[2])

                            if let aVersion = someVersions.first( where:{ $0.cropForCaptureOne.origin.x.distance( to: coOrigin.x ) < 1.0 } ) {
                                if !equalSize(coSize, aVersion.crop.size  , epsilon: 1.0) ||
                                    !(coOrigin.y.distance(to: aVersion.cropForCaptureOne.origin.y ) < 1.0) {
                                    let dx = (coSize.width - aVersion.crop.size.width) / imageSize.width
                                    let dy = (coSize.height - aVersion.crop.size.height) / imageSize.height

                                    let relativeSize = CGSize( width: dx * 100, height: dy * 100 )
                                    let apOrigin = aVersion.cropForCaptureOne.origin

                                    let correction = VersionCorrection( pk: variant_pk,
                                                                        crop: aVersion.cropForCaptureOne,
                                                                        imageSize: coSize,
                                                                        rotation: aVersion.rotation )

                                    print( "\(name) \(imageSize) [ap:\(aVersion.imageSize)] \(Int( aVersion.rotation )):\n\(CGRect( origin:coOrigin, size:coSize)) replaced by \(aVersion.cropForCaptureOne) -(clip)-> \(correction.clippedCrop)\n"  )
                                    // print( aVersion ?? "\(name) Not found", "\n       ", size, coordinates ) // , (image["zadjustmentlayer"] as Int) == variant_pk )

                                    correctionsToApply.append( correction )

                                    non_matches += 1
                                } else {
                                    print( "\(name) has an identical crop in Capture One" )
                                    matches += 1
                                }

                            } else {
                                missing += 1
                                print( "No aperture version with origin \(coOrigin) found in \(someVersions) for \(name) [\(someVersions.map{ $0.cropForCaptureOne.origin })]" )
                            }

                        }
                    }
                } catch {
                    print ( error );
                }
            }
        }
    }
} catch {
    print( "\(error)")
}

// print preprocessing stats
print( "\(matches) matches vs \(non_matches) [Missing:\(missing)]")

if writeChanges {
    print( "**** Updating crops in in Capture One versions" )

    // now throw the modifications on the images in the database:
    do {
        try c1Queue.inTransaction(.exclusive) {
            db in
            try correctionsToApply.forEach() {
                let r = $0.clippedCrop
                // intentional use of x y H W instead of xywh - c1 swaps w and h for portrait images.
                let crop = String( format:"%.06f;%.06f;%06f;%.06f", r.origin.x,r.origin.y, r.size.height, r.size.width )
                try db.execute(
                        sql: "UPDATE zvariantlayer SET zcrop = :crop WHERE z_pk = :pk",
                    arguments: ["crop": crop, "pk": $0.pk])
            }
            return .commit
        }
    }
    catch {
        print( "Error correcting version \(error)" )
    }
}

print( "**** Done" )

