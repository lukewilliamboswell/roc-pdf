# Gate 2 object identity plan

`KernelGate2Objects` joins the opaque tagged, color, image, resource-use, and
content plans before assigning PDF object numbers. The order is fixed by object
family: catalog, structure root, ParentTree, namespaces, semantic structure
elements, contextual Artifact structure elements, balanced page-tree nodes,
page/content pairs, ICC profile streams, color-space objects, image streams, and
optional alpha-mask streams. The xref stream follows the stored object range and
is not counted as a stored object.

All family sizes use checked arithmetic and the total object limit is enforced
before any object builder exists. Forward references therefore use planned
identities rather than placeholders or a repair pass. Alpha-mask variability is
handled by one linear prefix walk over image descriptors.

The plan stores only dense scalar object identities, page-tree shape facts, and
small fixed-shape rows. It does not retain a second scene, semantic store,
content byte stream, ICC profile, raster plane, or JPEG payload. Work counters
separate every variable object family so object growth remains reviewable before
the final dictionary/stream builder is introduced.
