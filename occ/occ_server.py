"""DIY.CAD — OpenCASCADE (OCP) B-rep çekirdek sunucusu.

Godot bu betiği yardımcı süreç olarak başlatır ve stdin/stdout üzerinden satır başına
bir JSON mesajla konuşur. Taslak eğrileri Godot tarafında dünya düzlemi + 2B eğri
listesi olarak hazırlanır; burada gerçek yüzey/kenar topolojisi (B-rep) kurulur,
Boolean işlemleri, köşe yuvarlatma, pah, kabuk, eğim, kaburga, çoklu gövde işlemleri,
STEP/IGES yapılır ve sonuç üçgenlenmiş ağ + kenar çoklu çizgileri + yüz bilgisi +
kütle özellikleri olarak döner.

Topolojik adlandırma: her yüz, onu üreten özellik ve taslak eğrisinden türetilen kalıcı bir
ad taşır (ör. "F3:s:12" = 3 numaralı ekstrüzyonun 12 numaralı taslak öğesinden çıkan yan yüzü).
Adlar her işlemde OCCT'nin geçmiş (Modified/Generated/IsDeleted) bilgisiyle taşınır. Kenarlar
komşu yüzlerinin adlarıyla, yüzler kendi adlarıyla başvurulur; ad bulunamazsa geometrik imzaya düşülür.

İstek:  {"id": n, "cmd": "ping" | "rebuild" | "export" | "quit", ...}
Yanıt:  {"id": n, "ok": true/false, ...}
"""
import sys
import os
import json
import base64
import hashlib
import math
import array
import time
import traceback


# Protokol kanalı: asıl stdout'un kopyası. OCCT'nin C++ tarafı (STEP/IGES mesajları) std::cout'a
# yazdığı için fd 1 stderr'e yönlendirilir; böylece JSON satırları hiçbir zaman bozulmaz.
try:
    _PROTO = os.fdopen(os.dup(1), "w", encoding="utf-8", newline="\n")
    os.dup2(2, 1)
    sys.stdout = sys.stderr
except OSError:  # pragma: no cover
    _PROTO = sys.stdout


def send(obj):
    _PROTO.write(json.dumps(obj, separators=(",", ":")) + "\n")
    _PROTO.flush()


try:
    from OCP.gp import gp_Pnt, gp_Vec, gp_Dir, gp_Ax1, gp_Ax2, gp_Ax3, gp_Pln, gp_Circ, gp_Elips, gp_Trsf
    from OCP.GC import GC_MakeArcOfCircle
    from OCP.Geom import Geom_Parabola, Geom_Plane
    from OCP.GeomAPI import GeomAPI_Interpolate
    try:  # OCCT 7.x adları
        from OCP.TColgp import TColgp_HArray1OfPnt
        from OCP.TopTools import TopTools_IndexedMapOfShape, TopTools_ListOfShape, TopTools_IndexedDataMapOfShapeListOfShape
    except ImportError:  # OCCT 8.x: şablon koleksiyonlar OCP.collections altında
        from OCP.collections import (HArray1_gp_Pnt as TColgp_HArray1OfPnt,
                                     IndexedMap_TopoDS_Shape_TopTools_ShapeMapHasher as TopTools_IndexedMapOfShape,
                                     List_TopoDS_Shape as TopTools_ListOfShape,
                                     IndexedDataMap_TopoDS_Shape_List_TopoDS_Shape_TopTools_ShapeMapHasher as TopTools_IndexedDataMapOfShapeListOfShape)
    from OCP.BRepBuilderAPI import (BRepBuilderAPI_MakeEdge, BRepBuilderAPI_MakeWire, BRepBuilderAPI_MakeFace,
                                    BRepBuilderAPI_Transform, BRepBuilderAPI_MakeVertex, BRepBuilderAPI_MakeSolid,
                                    BRepBuilderAPI_Sewing)
    from OCP.BRepPrimAPI import BRepPrimAPI_MakePrism, BRepPrimAPI_MakeRevol
    from OCP.BRepAlgoAPI import BRepAlgoAPI_Fuse, BRepAlgoAPI_Cut, BRepAlgoAPI_Common, BRepAlgoAPI_Splitter
    from OCP.BRepFilletAPI import BRepFilletAPI_MakeFillet, BRepFilletAPI_MakeChamfer
    from OCP.BRepOffsetAPI import (BRepOffsetAPI_MakeThickSolid, BRepOffsetAPI_MakeOffsetShape, BRepOffsetAPI_DraftAngle,
                                   BRepOffsetAPI_MakePipe, BRepOffsetAPI_MakePipeShell)
    from OCP.BRepFeat import BRepFeat_MakeLinearForm
    from OCP.BRepMesh import BRepMesh_IncrementalMesh
    from OCP.BRep import BRep_Tool, BRep_Builder
    from OCP.TopExp import TopExp, TopExp_Explorer
    from OCP.TopAbs import TopAbs_FACE, TopAbs_EDGE, TopAbs_SOLID, TopAbs_SHELL, TopAbs_REVERSED, TopAbs_IN, TopAbs_WIRE
    from OCP.TopoDS import TopoDS, TopoDS_Compound
    from OCP.TopLoc import TopLoc_Location
    from OCP.BRepAdaptor import BRepAdaptor_Curve, BRepAdaptor_Surface
    from OCP.GCPnts import GCPnts_QuasiUniformDeflection
    from OCP.GeomAbs import (GeomAbs_Plane, GeomAbs_Cylinder, GeomAbs_Cone, GeomAbs_Sphere, GeomAbs_Torus,
                             GeomAbs_BSplineSurface, GeomAbs_BezierSurface, GeomAbs_SurfaceOfRevolution,
                             GeomAbs_SurfaceOfExtrusion, GeomAbs_Line, GeomAbs_Circle, GeomAbs_Ellipse)
    from OCP.BRepGProp import BRepGProp, BRepGProp_Face
    from OCP.GProp import GProp_GProps
    from OCP.STEPControl import STEPControl_Writer, STEPControl_Reader, STEPControl_AsIs
    from OCP.IGESControl import IGESControl_Writer, IGESControl_Reader
    from OCP.IFSelect import IFSelect_RetDone
    from OCP.ShapeFix import ShapeFix_Face, ShapeFix_Shape, ShapeFix_Solid
    from OCP.ShapeUpgrade import ShapeUpgrade_UnifySameDomain
    from OCP.ShapeAnalysis import ShapeAnalysis_Surface
    from OCP.BRepExtrema import BRepExtrema_DistShapeShape
    from OCP.BRepClass import BRepClass_FaceClassifier
    from OCP.Bnd import Bnd_Box
    from OCP.BRepBndLib import BRepBndLib
    from OCP.BRepCheck import BRepCheck_Analyzer
except Exception as exc:  # pragma: no cover - ortam hatası
    send({"id": 0, "ready": False, "error": "OCP yüklenemedi: %s" % exc})
    sys.exit(1)

try:
    import OCP as _ocp
    OCP_VERSION = str(getattr(_ocp, "__version__", "?"))
except Exception:
    OCP_VERSION = "?"

THROUGH_ALL = 10000.0

# TopoDS dönüştürücüleri: OCCT 7.x'te statik (Face_s), 8.x'te ad alanı fonksiyonu (Face)
as_face = getattr(TopoDS, "Face_s", None) or TopoDS.Face
as_edge = getattr(TopoDS, "Edge_s", None) or TopoDS.Edge
as_shell = getattr(TopoDS, "Shell_s", None) or TopoDS.Shell
as_solid = getattr(TopoDS, "Solid_s", None) or TopoDS.Solid
as_wire = getattr(TopoDS, "Wire_s", None) or TopoDS.Wire


class KernelError(Exception):
    pass


# ---------------------------------------------------------------- yardımcılar

def b64f(values):
    return base64.b64encode(array.array("f", values).tobytes()).decode("ascii")


def b64i(values):
    return base64.b64encode(array.array("i", values).tobytes()).decode("ascii")


def vec3(p):
    return [p.X(), p.Y(), p.Z()]


def dot3(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def bbox_of(shape):
    box = Bnd_Box()
    BRepBndLib.Add_s(shape, box)
    if box.IsVoid():
        return None
    p0, p1 = box.CornerMin(), box.CornerMax()   # Get() OCCT 8'de dönüştürülemiyor
    return (p0.X(), p0.Y(), p0.Z(), p1.X(), p1.Y(), p1.Z())


def diag_of(shape):
    b = bbox_of(shape)
    if b is None:
        return 1.0
    return max(1e-6, math.sqrt((b[3] - b[0]) ** 2 + (b[4] - b[1]) ** 2 + (b[5] - b[2]) ** 2))


def shape_list(shape, kind):
    m = TopTools_IndexedMapOfShape()
    TopExp.MapShapes_s(shape, kind, m)
    return [m.FindKey(i) for i in range(1, m.Extent() + 1)]


def faces_of(shape):
    return [as_face(f) for f in shape_list(shape, TopAbs_FACE)]


def edges_of(shape):
    return [as_edge(e) for e in shape_list(shape, TopAbs_EDGE)]


def is_empty_shape(shape):
    return shape is None or shape.IsNull() or not shape_list(shape, TopAbs_FACE)


def compound(shapes):
    comp = TopoDS_Compound()
    b = BRep_Builder()
    b.MakeCompound(comp)
    for s in shapes:
        b.Add(comp, s)
    return comp


def solids_of(shape):
    if shape is None or shape.IsNull():
        return []
    return [as_solid(s) for s in shape_list(shape, TopAbs_SOLID)]


def surfaces_of(shape):
    """Bileşikteki katıya ait olmayan kabuk / yüz gövdeleri (Faz 8 yüzey modelleme)."""
    from OCP.TopoDS import TopoDS_Iterator
    from OCP.TopAbs import TopAbs_SHELL, TopAbs_FACE, TopAbs_COMPOUND
    out = []
    if shape is None or shape.IsNull():
        return out
    t = shape.ShapeType()
    if t in (TopAbs_SHELL, TopAbs_FACE):
        return [shape]
    if t != TopAbs_COMPOUND:
        return out
    it = TopoDS_Iterator(shape)
    while it.More():
        out += surfaces_of(it.Value())
        it.Next()
    return out


def lst(shapes):
    out = TopTools_ListOfShape()
    for s in shapes:
        out.Append(s)
    return out


def trsf_translate(v):
    t = gp_Trsf()
    t.SetTranslation(gp_Vec(*v))
    return t


def volume_of(shape):
    p = GProp_GProps()
    BRepGProp.VolumeProperties_s(shape, p)
    return p.Mass()


def centroid_of(shape):
    p = GProp_GProps()
    BRepGProp.VolumeProperties_s(shape, p)
    return vec3(p.CentreOfMass())


# ---------------------------------------------------------------- topolojik adlar

class NameMap:
    """Yüz -> kalıcı ad. TopoDS_Shape'in __eq__'i kimlik karşılaştırması olduğu için
    hash (yönelimden bağımsız) + IsSame ile aranır."""

    def __init__(self):
        self.d = {}

    def get(self, f):
        for g, n in self.d.get(hash(f), ()):
            if g.IsSame(f):
                return n
        return None

    def add(self, f, n):
        """Ad atar; yüzün zaten adı varsa kararlılık için sözlük sırasında küçük olan kalır."""
        bucket = self.d.setdefault(hash(f), [])
        for i, (g, old) in enumerate(bucket):
            if g.IsSame(f):
                if n < old:
                    bucket[i] = (f, n)
                return
        bucket.append((f, n))

    def items(self):
        for bucket in self.d.values():
            for g, n in bucket:
                yield g, n

    def merged(self, other):
        out = NameMap()
        for g, n in self.items():
            out.add(g, n)
        for g, n in other.items():
            out.add(g, n)
        return out


class Part:
    """Gövde(ler) + yüz adları. Önbellekte değiştirilmeden tutulur."""

    def __init__(self, shape=None, names=None):
        self.shape = shape
        self.names = names if names is not None else NameMap()

    def empty(self):
        return is_empty_shape(self.shape)


def carry(names, mk, extra=None):
    """Adları bir OCCT işleminin geçmişiyle yeni şekle taşır (Modified/IsDeleted)."""
    out = NameMap()
    for f, n in names.items():
        try:
            if mk.IsDeleted(f):
                continue
            mods = list(mk.Modified(f))
        except Exception:
            mods = []
        if mods:
            for m in mods:
                out.add(m, n)
        else:
            out.add(f, n)
    if extra is not None:
        for f, n in extra.items():
            out.add(f, n)
    return out


def carry_history(names, hist):
    out = NameMap()
    for f, n in names.items():
        if hist.IsRemoved(f):
            continue
        mods = list(hist.Modified(f))
        if mods:
            for m in mods:
                out.add(m, n)
        else:
            out.add(f, n)
    return out


def name_new_faces(shape, names, prefix):
    """Adı olmayan yüzlere özellik önekiyle yedek ad verir (yüz sırasına göre)."""
    k = 0
    for f in faces_of(shape):
        if names.get(f) is None:
            names.add(f, "%s:n%d" % (prefix, k))
            k += 1


def unify(part):
    try:
        u = ShapeUpgrade_UnifySameDomain(part.shape, True, True, False)
        u.Build()
        return Part(u.Shape(), carry_history(part.names, u.History()))
    except Exception:
        return part


def edge_face_map(shape):
    anc = TopTools_IndexedDataMapOfShapeListOfShape()
    TopExp.MapShapesAndAncestors_s(shape, TopAbs_EDGE, TopAbs_FACE, anc)
    return anc


def edge_name(part, e, anc=None):
    if anc is None:
        anc = edge_face_map(part.shape)
    idx = anc.FindIndex(e)
    if idx <= 0:
        return []
    names = []
    for f in anc.FindFromIndex(idx):
        n = part.names.get(f) or "?"
        if n not in names:
            names.append(n)
    return sorted(names)


# ---------------------------------------------------------------- taslak düzlemi ve eğriler

class Plane:
    def __init__(self, d):
        self.o = [float(v) for v in d["o"]]
        self.x = [float(v) for v in d["x"]]
        self.y = [float(v) for v in d["y"]]
        self.n = [float(v) for v in d["n"]]

    def w(self, p):
        u, v = float(p[0]), float(p[1])
        return [self.o[i] + self.x[i] * u + self.y[i] * v for i in range(3)]

    def pnt(self, p):
        return gp_Pnt(*self.w(p))

    def dir2(self, d):
        return gp_Dir(*[self.x[i] * float(d[0]) + self.y[i] * float(d[1]) for i in range(3)])

    def ax3(self):
        return gp_Ax3(gp_Pnt(*self.o), gp_Dir(*self.n), gp_Dir(*self.x))

    def pln(self):
        return gp_Pln(self.ax3())


def curve_edges(pl, c):
    t = c["t"]
    if t == "line":
        a, b = pl.pnt(c["a"]), pl.pnt(c["b"])
        if a.Distance(b) < 1e-9:
            return []
        return [BRepBuilderAPI_MakeEdge(a, b).Edge()]
    if t == "arc":
        p = [pl.pnt(q) for q in c["p"]]
        arc = GC_MakeArcOfCircle(p[0], p[1], p[2]).Value()
        return [BRepBuilderAPI_MakeEdge(arc).Edge()]
    if t == "circle":
        ax = gp_Ax2(pl.pnt(c["c"]), gp_Dir(*pl.n), gp_Dir(*pl.x))
        return [BRepBuilderAPI_MakeEdge(gp_Circ(ax, float(c["r"]))).Edge()]
    if t == "ellipse":
        a, b, phi = float(c["a"]), float(c["b"]), float(c["phi"])
        if a < b:  # gp_Elips büyük yarı ekseni X yönünde ister
            a, b, phi = b, a, phi + math.pi / 2.0
        xd = pl.dir2([math.cos(phi), math.sin(phi)])
        ax = gp_Ax2(pl.pnt(c["c"]), gp_Dir(*pl.n), xd)
        return [BRepBuilderAPI_MakeEdge(gp_Elips(ax, a, b)).Edge()]
    if t == "parabola":
        # gp/Geom parabol: P(U) = O + U²/(4F)·XDir + U·YDir,  YDir = N × XDir (taslaktaki w ile aynı)
        ax = gp_Ax2(pl.pnt(c["v"]), gp_Dir(*pl.n), pl.dir2(c["u"]))
        g = Geom_Parabola(ax, float(c["fl"]))
        w0, w1 = float(c["w0"]), float(c["w1"])
        if w0 > w1:
            w0, w1 = w1, w0
        return [BRepBuilderAPI_MakeEdge(g, w0, w1).Edge()]
    if t == "bspline":
        pts = list(c["p"])
        closed = bool(c.get("closed", False))
        if closed and len(pts) > 2:
            pts = pts[:-1]
        if len(pts) < 2:
            return []
        if len(pts) == 2 and not closed:
            return [BRepBuilderAPI_MakeEdge(pl.pnt(pts[0]), pl.pnt(pts[1])).Edge()]
        arr = TColgp_HArray1OfPnt(1, len(pts))
        for i, q in enumerate(pts):
            arr.SetValue(i + 1, pl.pnt(q))
        it = GeomAPI_Interpolate(arr, closed, 1e-7)
        it.Perform()
        if not it.IsDone():
            raise KernelError("Spline oluşturulamadı")
        return [BRepBuilderAPI_MakeEdge(it.Curve()).Edge()]
    if t == "poly":
        pts = [pl.pnt(q) for q in c["p"]]
        out = []
        for i in range(len(pts)):
            a, b = pts[i], pts[(i + 1) % len(pts)]
            if a.Distance(b) > 1e-9:
                out.append(BRepBuilderAPI_MakeEdge(a, b).Edge())
        return out
    raise KernelError("Bilinmeyen eğri türü: %s" % t)


class EdgeKeys:
    """Oluşturulan taslak kenarı -> taslak öğe anahtarı ("k"). Kenarlar sonradan kopyalanabildiği
    (tel/yüz kurulurken, bölme sırasında) için önce IsSame, sonra eğri üzerinde olma ile eşlenir."""

    def __init__(self):
        self.items = []
        self._by_hash = {}
        self._mids = None

    def add(self, e, k):
        self.items.append((e, k))
        self._by_hash.setdefault(hash(e), []).append((e, k))
        self._mids = None

    def build(self, pl, c):
        es = curve_edges(pl, c)
        k = str(c.get("k", "?"))
        for i, e in enumerate(es):
            self.add(e, k if len(es) == 1 else "%s.%d" % (k, i))
        return es

    def key_of(self, e):
        for g, k in self._by_hash.get(hash(e), ()):
            if g.IsSame(e):
                return k
        m = edge_signature(e)["m"]
        if self._mids is None:
            self._mids = [(edge_signature(g)["m"], bbox_of(g), g, k) for g, k in self.items]
        for gm, _b, _g, k in self._mids:
            if math.dist(gm, m) < 1e-6:
                return k
        # Son çare: kenar orta noktası hangi taslak kenarının üzerinde (önce sınır kutusu süzgeci)
        best, bd = None, 1e-5
        for _gm, b, g, k in self._mids:
            if b is None or not (b[0] - 1e-4 <= m[0] <= b[3] + 1e-4 and b[1] - 1e-4 <= m[1] <= b[4] + 1e-4
                                 and b[2] - 1e-4 <= m[2] <= b[5] + 1e-4):
                continue
            d = dist_to(m, g)
            if d < bd:
                best, bd = k, d
        return best


def make_wire(edges):
    mw = BRepBuilderAPI_MakeWire()
    for e in edges:
        mw.Add(e)
    if not mw.IsDone():
        raise KernelError("Kontur kenarları birleştirilemedi")
    return mw.Wire()


def face_normal_dir(face):
    """Düzlemsel yüzün (yönelimi hesaba katılmış) normali."""
    s = BRepAdaptor_Surface(face)
    if s.GetType() != GeomAbs_Plane:
        return None
    d = s.Plane().Axis().Direction()
    n = [d.X(), d.Y(), d.Z()]
    if face.Orientation() == TopAbs_REVERSED:
        n = [-v for v in n]
    return n


def orient_face(face, n):
    fn = face_normal_dir(face)
    if fn is not None and dot3(fn, n) < 0.0:
        return as_face(face.Reversed())
    return face


def faces_from_loops(pl, loops, keys):
    wires = []
    for L in loops:
        edges = []
        for c in L["curves"]:
            edges.extend(keys.build(pl, c))
        wires.append(make_wire(edges) if edges else None)
    faces = []
    for i, L in enumerate(loops):
        if int(L["depth"]) % 2 != 0 or wires[i] is None:
            continue
        mf = BRepBuilderAPI_MakeFace(pl.pln(), wires[i], True)
        for j, H in enumerate(loops):
            if int(H.get("parent", -1)) == i and int(H["depth"]) % 2 == 1 and wires[j] is not None:
                mf.Add(wires[j])
        if not mf.IsDone():
            raise KernelError("Profil yüzü oluşturulamadı")
        sf = ShapeFix_Face(mf.Face())
        sf.FixOrientation()
        sf.Perform()
        faces.append(orient_face(as_face(sf.Face()), pl.n))
    if not faces:
        raise KernelError("Taslakta kapalı kontur yok")
    return faces


def region_faces(pl, curves, samples, keys):
    """Kesişen eğrilerin oluşturduğu bölgelerden örnek noktaları içerenler (Contour Select)."""
    edges = []
    us, vs = [], []
    for c in curves:
        edges.extend(keys.build(pl, c))
    if not edges:
        raise KernelError("Taslakta eğri yok")
    for e in edges:
        b = bbox_of(e)
        for corner in ((b[0], b[1], b[2]), (b[3], b[4], b[5])):
            d = [corner[i] - pl.o[i] for i in range(3)]
            us.append(dot3(d, pl.x))
            vs.append(dot3(d, pl.y))
    m = max(max(us) - min(us), max(vs) - min(vs)) * 0.1 + 1.0
    big = BRepBuilderAPI_MakeFace(pl.pln(), min(us) - m, max(us) + m, min(vs) - m, max(vs) + m).Face()
    sp = BRepAlgoAPI_Splitter()
    sp.SetArguments(lst([big]))
    sp.SetTools(lst(edges))
    sp.Build()
    if not sp.IsDone():
        raise KernelError("Bölgeler hesaplanamadı")
    # Bölünen kenar parçalarını anahtarlarına bağla
    for e, k in list(keys.items):
        for piece in sp.Modified(e):
            keys.add(piece, k)
    pieces = faces_of(sp.Shape())
    chosen = []
    for s in samples:
        p = pl.pnt(s)
        for i, f in enumerate(pieces):
            if i in chosen:
                continue
            if BRepClass_FaceClassifier(f, p, 1e-6).State() == TopAbs_IN:
                chosen.append(i)
                break
    if not chosen:
        raise KernelError("Seçili bölgeler bulunamadı (taslak değişmiş olabilir)")
    return [orient_face(pieces[i], pl.n) for i in chosen]


def profile_faces(f, pl, keys):
    if "regions" in f:
        return region_faces(pl, f["regions"]["curves"], f["regions"]["samples"], keys)
    return faces_from_loops(pl, f["loops"], keys)


def cap_key(face, keys):
    ks = sorted(k for k in (keys.key_of(e) for e in edges_of(face)) if k is not None)
    return ks[0] if ks else "?"


# ---------------------------------------------------------------- kenar / yüz başvuruları

def _vertex(p):
    return BRepBuilderAPI_MakeVertex(gp_Pnt(*p)).Vertex()


def dist_to(p, shape):
    d = BRepExtrema_DistShapeShape(_vertex(p), shape)
    if not d.IsDone() or d.NbSolution() == 0:
        return 1e30
    return d.Value()


def shape_dist(a, b):
    d = BRepExtrema_DistShapeShape(a, b)
    if not d.IsDone() or d.NbSolution() == 0:
        return 1e30
    return d.Value()


def edge_signature(e):
    c = BRepAdaptor_Curve(e)
    u = 0.5 * (c.FirstParameter() + c.LastParameter())
    p = gp_Pnt()
    v = gp_Vec()
    c.D1(u, p, v)
    ln = v.Magnitude()
    d = [v.X() / ln, v.Y() / ln, v.Z() / ln] if ln > 1e-12 else [0.0, 0.0, 0.0]
    return {"m": vec3(p), "d": d}


def usable_edges(shape):
    return [as_edge(e) for e in shape_list(shape, TopAbs_EDGE) if not BRep_Tool.Degenerated_s(as_edge(e))]


def _geo_score(ref, sig, e, diag):
    m = [float(v) for v in ref["m"]]
    rd = [float(v) for v in ref.get("d", [0, 0, 0])]
    dm = math.dist(m, sig["m"])
    # Kenarın kendisi kayıtlı noktadan geçiyorsa (uzama/kısalma) tercih edilir
    on = dm if dm < 1e-4 else dist_to(m, e) if dm < 0.3 * diag else 1e30
    par = abs(dot3(rd, sig["d"]))
    return (0.0 if on < 1e-4 else dm) + (0.0 if par > 0.95 or rd == [0, 0, 0] else 0.05 * diag)


def resolve_edges(part, refs):
    """Kenar başvurularını çözer: önce komşu yüz adları (topolojik), sonra geometrik imza."""
    shape = part.shape
    edges = usable_edges(shape)
    if not edges:
        raise KernelError("Gövdede kenar yok")
    diag = diag_of(shape)
    anc = edge_face_map(shape)
    sigs = [edge_signature(e) for e in edges]
    fns = [edge_name(part, e, anc) for e in edges]
    out, new_refs, missing, by_name = [], [], 0, 0
    for ref in refs:
        want = sorted(ref.get("fn", []))
        cand = [i for i in range(len(edges)) if i not in out and want and "?" not in want and fns[i] == want]
        best = -1
        if cand:
            best = min(cand, key=lambda i: math.dist([float(v) for v in ref["m"]], sigs[i]["m"]))
            by_name += 1
        else:
            bscore = 1e30
            for i, e in enumerate(edges):
                if i in out:
                    continue
                score = _geo_score(ref, sigs[i], e, diag)
                if score < bscore:
                    best, bscore = i, score
            if best >= 0 and bscore > 0.25 * diag:
                best = -1
        if best < 0:
            missing += 1
            continue
        out.append(best)
        r = dict(sigs[best])
        r["fn"] = fns[best]
        new_refs.append(r)
    if missing and not out:
        raise KernelError("Seçili kenarlar bulunamadı (model değişmiş olabilir)")
    return [edges[i] for i in out], new_refs, missing


def face_normal_at(face, p):
    sa = ShapeAnalysis_Surface(BRep_Tool.Surface_s(face))
    uv = sa.ValueOfUV(gp_Pnt(*p), 1e-6)
    pp = gp_Pnt()
    vn = gp_Vec()
    BRepGProp_Face(face).Normal(uv.X(), uv.Y(), pp, vn)
    ln = vn.Magnitude()
    if ln < 1e-12:
        return [0.0, 0.0, 0.0]
    return [vn.X() / ln, vn.Y() / ln, vn.Z() / ln]


def _face_point(face):
    props = GProp_GProps()
    BRepGProp.SurfaceProperties_s(face, props)
    c = props.CentreOfMass()
    # Ağırlık merkezi yüzün dışında olabilir (ör. halka): yüze izdüşür
    d = BRepExtrema_DistShapeShape(BRepBuilderAPI_MakeVertex(c).Vertex(), face)
    if d.IsDone() and d.NbSolution() > 0:
        return vec3(d.PointOnShape2(1))
    return vec3(c)


def resolve_face(part, ref, exclude=()):
    """Tek yüz başvurusu: ad eşleşmesi (en yakın parça) yoksa nokta + normal."""
    faces = faces_of(part.shape)
    p = [float(v) for v in ref["p"]]
    n = [float(v) for v in ref.get("n", [0, 0, 0])]
    want = ref.get("name", "")
    if want:
        cand = [i for i, f in enumerate(faces) if i not in exclude and part.names.get(f) == want]
        if cand:
            return min(cand, key=lambda i: dist_to(p, faces[i])), faces
    diag = diag_of(part.shape)
    best, bscore = -1, 1e30
    for i, f in enumerate(faces):
        if i in exclude:
            continue
        d = dist_to(p, f)
        if d > 0.25 * diag:
            continue
        dot = dot3(face_normal_at(f, p), n)
        score = d + (0.0 if dot > 0.98 else 0.1 * diag)
        if score < bscore:
            best, bscore = i, score
    if best >= 0 and bscore < 0.25 * diag:
        return best, faces
    return -1, faces


def face_ref_of(part, face, p_hint=None):
    p = p_hint if p_hint is not None else _face_point(face)
    if dist_to(p, face) > 1e-4:
        p = _face_point(face)
    return {"p": p, "n": face_normal_at(face, p), "name": part.names.get(face) or ""}


def resolve_faces(part, refs):
    out, new_refs = [], []
    faces = []
    for ref in refs:
        i, faces = resolve_face(part, ref, out)
        if i >= 0:
            out.append(i)
            new_refs.append(face_ref_of(part, faces[i], [float(v) for v in ref["p"]]))
    if refs and not out:
        raise KernelError("Seçili yüzler bulunamadı (model değişmiş olabilir)")
    return [faces[i] for i in out], new_refs


def resolve_body(part, ref):
    """Gövde başvurusu {p, name}: adı taşıyan yüzün gövdesi, yoksa noktaya en yakın gövde."""
    bodies = solids_of(part.shape)
    if not bodies:
        raise KernelError("Model gövde içermiyor")
    want = ref.get("name", "")
    if want:
        for i, b in enumerate(bodies):
            for f in faces_of(b):
                if part.names.get(f) == want:
                    return i, bodies
    p = [float(v) for v in ref["p"]]
    best = min(range(len(bodies)), key=lambda i: dist_to(p, bodies[i]))
    if dist_to(p, bodies[best]) > 0.25 * diag_of(part.shape):
        raise KernelError("Seçili gövde bulunamadı")
    return best, bodies


def body_ref_of(part, body, p_hint):
    faces = faces_of(body)
    best = min(faces, key=lambda f: dist_to(p_hint, f))
    return {"p": p_hint, "name": part.names.get(best) or ""}


# ---------------------------------------------------------------- Boolean ve gövdeler

def boolean(part, tool, cut, merge=True, fid=0):
    """tool: Part. merge=False ise araç ayrı gövde olarak eklenir; birleştirmede yalnızca
    araca değen gövdeler birleşir, diğer gövdeler aynen kalır."""
    if part is None or part.empty():
        if cut:
            raise KernelError("Kesilecek gövde yok")
        return tool
    bodies = solids_of(part.shape)
    surfs = surfaces_of(part.shape)
    if surfs and not cut:
        # Yüzey gövdeleri katı işlemlerinden etkilenmez, aynen taşınır
        rest_part = Part(compound(bodies), part.names) if bodies else None
        res = boolean(rest_part, tool, cut, merge, fid)
        return Part(compound(solids_of(res.shape) + surfaces_of(res.shape) + surfs), res.names.merged(part.names))
    if cut:
        op = BRepAlgoAPI_Cut(part.shape, tool.shape)
    elif not merge:
        return Part(compound(bodies + solids_of(tool.shape) + surfaces_of(tool.shape)), part.names.merged(tool.names))
    else:
        touching = [b for b in bodies if shape_dist(b, tool.shape) <= 1e-6]
        if not touching:
            return Part(compound(bodies + solids_of(tool.shape)), part.names.merged(tool.names))
        rest = [b for b in bodies if not any(b.IsSame(t) for t in touching)]
        op = BRepAlgoAPI_Fuse(compound(touching) if len(touching) > 1 else touching[0], tool.shape)
        if not op.IsDone():
            raise KernelError("Boolean işlemi başarısız")
        res = op.Shape()
        names = carry(part.names.merged(tool.names), op)
        shape = compound(solids_of(res) + rest) if rest else res
        return unify(Part(shape, names))
    if not op.IsDone():
        raise KernelError("Boolean işlemi başarısız")
    return unify(Part(op.Shape(), carry(part.names.merged(tool.names), op)))


def replace_bodies(part, old_bodies, new_shape, names):
    """old_bodies'i new_shape'in katılarıyla değiştirir, diğer gövdeler korunur."""
    rest = [b for b in solids_of(part.shape) if not any(b.IsSame(o) for o in old_bodies)]
    return Part(compound(rest + solids_of(new_shape)), names)


# ---------------------------------------------------------------- özellikler

def _support_plane(part, f, pl, upd):
    """Yüzeye çizilen taslak: destek yüzü (ad/geometri) bulunur, düzlem yüzle birlikte kayar."""
    sup = f.get("support")
    if not sup or part is None or part.empty():
        return pl, [0.0, 0.0, 0.0]
    i, faces = resolve_face(part, sup)
    if i < 0:
        return pl, [0.0, 0.0, 0.0]
    face = faces[i]
    fn = face_normal_dir(face)
    if fn is None or abs(dot3(fn, pl.n)) < 0.999999:
        return pl, [0.0, 0.0, 0.0]
    fp = _face_point(face)
    off = dot3([fp[k] - pl.o[k] for k in range(3)], pl.n)
    if abs(off) < 1e-9:
        return pl, [0.0, 0.0, 0.0]
    delta = [pl.n[k] * off for k in range(3)]
    pl.o = [pl.o[k] + delta[k] for k in range(3)]
    upd["plane"] = {"fid": f.get("sketch_fid", 0), "o": pl.o}
    return pl, delta


UNTIL_L = 2.0e4


def _extended_face(face, offset=0.0):
    """Hedef yüzü (Yüzeye Kadar) kesici olarak kullanmak için genişletilmiş yüz; offset dış normal yönünde."""
    s = BRepAdaptor_Surface(face)
    st = s.GetType()
    sign = -1.0 if face.Orientation() == TopAbs_REVERSED else 1.0
    if st == GeomAbs_Plane:
        pln = s.Plane()
        d = pln.Axis().Direction()
        n = [d.X() * sign, d.Y() * sign, d.Z() * sign]
        o = vec3(pln.Location())
        o = [o[k] + n[k] * offset for k in range(3)]
        return BRepBuilderAPI_MakeFace(gp_Pln(gp_Pnt(*o), gp_Dir(*n)), -UNTIL_L, UNTIL_L, -UNTIL_L, UNTIL_L).Face()
    if st == GeomAbs_Cylinder:
        from OCP.Geom import Geom_CylindricalSurface
        cy = s.Cylinder()
        r = cy.Radius() + sign * offset
        if r <= 1e-9:
            raise KernelError("Ofset silindir yarıçapından büyük")
        surf = Geom_CylindricalSurface(cy.Position(), r)
        return BRepBuilderAPI_MakeFace(surf, 0.0, 2.0 * math.pi, -UNTIL_L, UNTIL_L, 1e-7).Face()
    if abs(offset) > 1e-12:
        from OCP.Geom import Geom_OffsetSurface
        u0, u1, v0, v1 = BRepTools_UVBounds(face)
        surf = Geom_OffsetSurface(BRep_Tool.Surface_s(face), sign * offset)
        return BRepBuilderAPI_MakeFace(surf, u0, u1, v0, v1, 1e-7).Face()
    return face


def BRepTools_UVBounds(face):
    from OCP.BRepTools import BRepTools
    return BRepTools.UVBounds_s(face)


def _next_face(part, start_pts, d):
    """Profilden çıkarma yönünde ilk karşılaşılan yüz (Sonrakine Kadar)."""
    from OCP.IntCurvesFace import IntCurvesFace_ShapeIntersector
    from OCP.gp import gp_Lin
    if part is None or part.empty():
        raise KernelError("Sonrakine Kadar için önünde bir gövde olmalı")
    si = IntCurvesFace_ShapeIntersector()
    si.Load(part.shape, 1e-7)
    best = None
    for p in start_pts:
        si.Perform(gp_Lin(gp_Pnt(*p), gp_Dir(*d)), 1e-6, 1e9)
        if not si.IsDone():
            continue
        for i in range(1, si.NbPnt() + 1):
            w = si.WParameter(i)
            if w > 1e-5 and (best is None or w < best[0]):
                best = (w, si.Face(i))
    if best is None:
        raise KernelError("Profilin önünde yüz bulunamadı (Sonrakine Kadar)")
    return best[1]


def _until_split(solid, target, offset, start):
    """Uzun prizmayı hedef yüzle böler, başlangıç profiline değen parçayı tutar."""
    ext = _extended_face(target, offset)
    sp = BRepAlgoAPI_Splitter()
    sp.SetArguments(lst([solid]))
    sp.SetTools(lst([ext]))
    sp.Build()
    if not sp.IsDone():
        raise KernelError("Hedef yüzle sınırlama başarısız")
    pieces = solids_of(sp.Shape())
    keep = [pc for pc in pieces if shape_dist(pc, start) < 1e-6]
    if not keep or len(pieces) < 2:
        raise KernelError("Hedef yüz profilin önünü kesmiyor")
    return keep[0] if len(keep) == 1 else compound(keep), sp


def _thick_strip(wire, vec, t, side):
    """Açık tel: telin prizma şeridi kalınlaştırılır (ince özellik, kare uçlar)."""
    strip = BRepPrimAPI_MakePrism(wire, gp_Vec(*vec), False, True).Shape()

    def th(off):
        mk = BRepOffsetAPI_MakeThickSolid()
        mk.MakeThickSolidBySimple(strip, off)
        mk.Build()
        if not mk.IsDone():
            raise KernelError("İnce özellik oluşturulamadı")
        sh = mk.Shape()
        if volume_of(sh) < 0:
            sh = sh.Reversed()
        return sh
    if side == "mid":
        op = BRepAlgoAPI_Fuse(th(t * 0.5), th(-t * 0.5))
        return op.Shape()
    return th(t if side == "a" else -t)


def _thin_face(pl, wire, t, side):
    """Kapalı tel: düzlemde içe/dışa ofset tellerle halka yüz."""
    from OCP.BRepOffsetAPI import BRepOffsetAPI_MakeOffset
    from OCP.GeomAbs import GeomAbs_Intersection

    def off(d):
        if abs(d) < 1e-12:
            return wire
        mo = BRepOffsetAPI_MakeOffset(wire, GeomAbs_Intersection, False)
        mo.Perform(d)
        if not mo.IsDone():
            raise KernelError("İnce özellik ofseti oluşturulamadı")
        ws = shape_list(mo.Shape(), TopAbs_WIRE)
        if not ws:
            raise KernelError("İnce özellik ofseti boş")
        return as_wire(ws[0])
    if side == "mid":
        outer, inner = off(t * 0.5), off(-t * 0.5)
    elif side == "a":
        outer, inner = off(t), wire
    else:
        outer, inner = wire, off(-t)
    fo = BRepBuilderAPI_MakeFace(pl.pln(), outer, True).Face()
    fi = BRepBuilderAPI_MakeFace(pl.pln(), inner, True).Face()
    op = BRepAlgoAPI_Cut(fo, fi)
    faces = faces_of(op.Shape())
    if not faces:
        raise KernelError("İnce özellik yüzü oluşturulamadı")
    return [orient_face(fc, pl.n) for fc in faces]


def _chain_wires(pl, chains, keys):
    out = []
    for ch in chains:
        edges = []
        for c in ch:
            edges.extend(keys.build(pl, c))
        if not edges:
            continue
        mw = BRepBuilderAPI_MakeWire()
        mw.Add(lst(edges))
        if not mw.IsDone():
            raise KernelError("Taslak zinciri birleştirilemedi")
        w = mw.Wire()
        out.append((w, BRep_Tool.IsClosed_s(w)))
    if not out:
        raise KernelError("Taslakta çizgi yok")
    return out


def _directional_tool(part, faces, wires, pl, keys, fid, vec, off, end, f, side_key, names):
    """Bir yön için ekstrüzyon katısı (kör/tümünden/sonrakine/yüzeye kadar, eğim, ince)."""
    thin = float(f.get("thin", 0.0))
    draft = float(f.get("draft", 0.0))
    d = [vec[k] for k in range(3)]
    ln = math.sqrt(dot3(d, d)) or 1.0
    dn = [v / ln for v in d]
    solids = []
    starts = []
    if thin > 0 and wires:
        side = str(f.get("thin_side", "mid"))
        for w, closed in wires:
            wc = w
            if abs(off[0]) + abs(off[1]) + abs(off[2]) > 1e-12:
                wc = as_wire(BRepBuilderAPI_Transform(w, trsf_translate(off), True).Shape())
            if closed:
                for fc in _thin_face(pl, wc, thin, side):
                    pr = BRepPrimAPI_MakePrism(fc, gp_Vec(*vec), False, True)
                    solids.append(pr.Shape())
                    starts.append(fc)
            else:
                solids.append(_thick_strip(wc, vec, thin, side))
                starts.append(wc)
    else:
        for face in faces:
            fc = face
            if abs(off[0]) + abs(off[1]) + abs(off[2]) > 1e-12:
                fc = as_face(BRepBuilderAPI_Transform(face, trsf_translate(off), True).Shape())
            pr = BRepPrimAPI_MakePrism(fc, gp_Vec(*vec), False, True)
            if not pr.IsDone():
                raise KernelError("Ekstrüzyon oluşturulamadı")
            ck = cap_key(fc, keys)
            sides = []
            for e in edges_of(fc):
                k = keys.key_of(e)
                for g in pr.Generated(e):
                    names.add(g, "F%s:%s:%s" % (fid, side_key, k if k is not None else "?"))
                    sides.append(as_face(g))
            names.add(pr.FirstShape(), "F%s:a:%s" % (fid, ck))
            names.add(pr.LastShape(), "F%s:%s:%s" % (fid, "b" if side_key == "s" else "c", ck))
            sol = pr.Shape()
            if abs(draft) > 1e-9:
                mk = BRepOffsetAPI_DraftAngle(sol)
                ang = math.radians(draft) * (-1.0 if f.get("draft_out", False) else 1.0)
                fp = _face_point(fc)
                pln = gp_Pln(gp_Pnt(*fp), gp_Dir(*dn))
                for sf in sides:
                    mk.Add(sf, gp_Dir(*dn), ang, pln, True)
                    if not mk.AddDone():
                        raise KernelError("Bu profile eğim verilemez")
                mk.Build()
                if not mk.IsDone():
                    raise KernelError("Eğimli ekstrüzyon oluşturulamadı (açı çok büyük olabilir)")
                tmp = carry(names, mk)
                names.d = tmp.d
                sol = mk.Shape()
            solids.append(sol)
            starts.append(fc)
    if end in ("next", "face", "face_offset"):
        if end == "next":
            pts = []
            for st in starts:
                if st.ShapeType() == TopAbs_FACE:
                    pts.append(_face_point(as_face(st)))
                else:
                    pts.append(edge_signature(edges_of(st)[0])["m"])
            target = _next_face(part, pts, dn)
            offset = 0.0
        else:
            if not f.get("face"):
                raise KernelError("Hedef yüz seçilmedi")
            ti, tfaces = resolve_face(part, f["face"])
            if ti < 0:
                raise KernelError("Hedef yüz bulunamadı")
            target = tfaces[ti]
            offset = float(f.get("face_off", 0.0)) if end == "face_offset" else 0.0
        cut_solids = []
        for sol, st in zip(solids, starts):
            piece, sp = _until_split(sol, target, offset, st)
            tmp = carry(names, sp)
            names.d = tmp.d
            cut_solids.append(piece)
        solids = cut_solids
    return solids


def feat_extrude(part, f, upd):
    pl = Plane(f["plane"])
    pl, delta = _support_plane(part, f, pl, upd)
    keys = EdgeKeys()
    fid = f["fid"]
    thin = float(f.get("thin", 0.0))
    wires, faces = [], []
    if thin > 0:
        wires = _chain_wires(pl, f.get("chains", []), keys)
    else:
        faces = profile_faces(f, pl, keys)
    vec = [float(v) for v in f["vec"]]
    off = [float(v) for v in f.get("offset", [0, 0, 0])]
    names = NameMap()
    end = str(f.get("end", "blind"))
    solids = _directional_tool(part, faces, wires, pl, keys, fid, vec, off, end, f, "s", names)
    d2 = f.get("dir2")
    if d2:
        f2 = dict(f)
        f2["face"] = d2.get("face")
        f2["face_off"] = d2.get("face_off", 0.0)
        solids += _directional_tool(part, faces, wires, pl, keys, fid, [float(v) for v in d2["vec"]], [0.0, 0.0, 0.0],
                                    str(d2.get("end", "blind")), f2, "t", names)
    if len(solids) > 1 and d2:
        acc = solids[0]
        for sh in solids[1:]:
            op = BRepAlgoAPI_Fuse(acc, sh)
            tmp = carry(names, op)
            names.d = tmp.d
            acc = op.Shape()
        tool = Part(acc, names)
    else:
        tool = Part(solids[0] if len(solids) == 1 else compound(solids), names)
    name_new_faces(tool.shape, tool.names, "F%s" % fid)
    cut = bool(f.get("cut", False))
    upd["_tool"] = (tool, cut)
    return boolean(part, tool, cut, bool(f.get("merge", True)), fid)


def feat_revolve(part, f, upd):
    pl = Plane(f["plane"])
    pl, delta = _support_plane(part, f, pl, upd)
    keys = EdgeKeys()
    faces = profile_faces(f, pl, keys)
    fid = f["fid"]
    ao = [float(f["axis_o"][k]) + delta[k] for k in range(3)]
    ax = gp_Ax1(gp_Pnt(*ao), gp_Dir(*f["axis_d"]))
    ang = math.radians(max(0.1, min(360.0, float(f["angle"]))))
    solids, names = [], NameMap()
    for face in faces:
        rv = BRepPrimAPI_MakeRevol(face, ax, ang, True)
        if not rv.IsDone():
            raise KernelError("Döndürme oluşturulamadı")
        ck = cap_key(face, keys)
        for e in edges_of(face):
            k = keys.key_of(e)
            for g in rv.Generated(e):
                names.add(g, "F%s:s:%s" % (fid, k if k is not None else "?"))
        if ang < 2.0 * math.pi - 1e-9:
            names.add(rv.FirstShape(), "F%s:a:%s" % (fid, ck))
            names.add(rv.LastShape(), "F%s:b:%s" % (fid, ck))
        solids.append(rv.Shape())
    tool = Part(solids[0] if len(solids) == 1 else compound(solids), names)
    upd["_tool"] = (tool, bool(f.get("cut", False)))
    return boolean(part, tool, bool(f.get("cut", False)), bool(f.get("merge", True)), fid)


def _edges_by_body(part, edges):
    """Kenarları ait oldukları gövdelere göre gruplar: [(gövde, [kenarlar])]."""
    groups = []
    for b in solids_of(part.shape):
        bedges = shape_list(b, TopAbs_EDGE)
        mine = [e for e in edges if any(e.IsSame(x) for x in bedges)]
        if mine:
            groups.append((b, mine))
    return groups


def _edge_op(part, f, upd, maker, label):
    if part is None or part.empty():
        raise KernelError("%s yapılacak gövde yok" % label)
    if not f.get("edges"):
        raise KernelError("Kenar seçilmedi")
    edges, refs, missing = resolve_edges(part, f["edges"])
    upd["edges"] = refs
    anc = edge_face_map(part.shape)
    enames = {id(e): "|".join(edge_name(part, e, anc)) for e in edges}
    new_bodies, names = [], part.names
    old = []
    extra = NameMap()
    for body, bedges in _edges_by_body(part, edges):
        mk = maker(body, bedges, anc)
        try:
            mk.Build()
        except Exception:
            pass
        if not mk.IsDone():
            raise KernelError("%s yapılamadı (ölçü komşu yüzlere sığmıyor olabilir)" % label)
        names = carry(names, mk)
        for e in bedges:
            for g in mk.Generated(e):
                extra.add(g, "F%s:%s:%s" % (f["fid"], label[0].lower(), enames.get(id(e), "?")))
        old.append(body)
        new_bodies.append(mk.Shape())
    names = names.merged(extra)
    if missing:
        upd["warn"] = "%d kenar bulunamadı" % missing
    out = replace_bodies(part, old, compound(new_bodies) if len(new_bodies) > 1 else new_bodies[0], names)
    name_new_faces(out.shape, out.names, "F%s" % f["fid"])
    return out


def feat_fillet(part, f, upd):
    r = float(f["r"])
    r2 = float(f.get("r2", r)) if f.get("variable", False) else r
    if r <= 0 or r2 <= 0:
        raise KernelError("Yarıçap sıfırdan büyük olmalı")

    def maker(body, bedges, anc):
        mk = BRepFilletAPI_MakeFillet(body)
        for e in bedges:
            if abs(r2 - r) > 1e-12:
                mk.Add(r, r2, e)
            else:
                mk.Add(r, e)
        return mk
    return _edge_op(part, f, upd, maker, "Fillet")


def feat_chamfer(part, f, upd):
    mode = f.get("mode", "equal")
    d = float(f["d"])
    d2 = float(f.get("d2", d))
    ang = math.radians(float(f.get("angle", 45.0)))
    if d <= 0 or (mode == "dist2" and d2 <= 0):
        raise KernelError("Mesafe sıfırdan büyük olmalı")
    if mode == "angle" and not (0.0 < ang < math.pi / 2.0):
        raise KernelError("Açı 0° ile 90° arasında olmalı")
    flip = bool(f.get("flip", False))

    def maker(body, bedges, anc):
        mk = BRepFilletAPI_MakeChamfer(body)
        for e in bedges:
            if mode == "equal":
                mk.Add(d, e)
                continue
            idx = anc.FindIndex(e)
            adj = [as_face(x) for x in anc.FindFromIndex(idx)] if idx > 0 else []
            if not adj:
                mk.Add(d, e)
                continue
            face = adj[1] if (flip and len(adj) > 1) else adj[0]
            if mode == "dist2":
                mk.Add(d, d2, e, face)
            else:
                mk.AddDA(d, ang, e, face)
        return mk
    return _edge_op(part, f, upd, maker, "Chamfer")


def feat_shell(part, f, upd):
    if part is None or part.empty():
        raise KernelError("Kabuk yapılacak gövde yok")
    t = float(f["t"])
    if t <= 0:
        raise KernelError("Kalınlık sıfırdan büyük olmalı")
    faces, refs = resolve_faces(part, f.get("faces", []))
    upd["faces"] = refs
    off = t if f.get("outward", False) else -t
    bodies = solids_of(part.shape)
    if faces:
        targets = [b for b in bodies if any(any(fc.IsSame(x) for x in faces_of(b)) for fc in faces)]
    else:
        targets = bodies[:1] if len(bodies) == 1 else bodies
    names = part.names
    news = []
    try:
        for body in targets:
            bf = faces_of(body)
            mine = [fc for fc in faces if any(fc.IsSame(x) for x in bf)]
            if mine:
                mk = BRepOffsetAPI_MakeThickSolid()
                mk.MakeThickSolidByJoin(body, lst(mine), off, 1e-4)
                mk.Build()
                if not mk.IsDone():
                    raise KernelError("x")
                names = carry(names, mk)
                news.append(mk.Shape())
            else:
                # Yüz kaldırılmadan: içi boş kapalı gövde (iç boşluk)
                mo = BRepOffsetAPI_MakeOffsetShape()
                mo.PerformByJoin(body, off, 1e-4)
                if not mo.IsDone():
                    raise KernelError("x")
                shells = shape_list(mo.Shape(), TopAbs_SHELL)
                if not shells:
                    raise KernelError("x")
                inner = BRepBuilderAPI_MakeSolid(as_shell(shells[0])).Solid()
                op = BRepAlgoAPI_Cut(body, inner) if off < 0 else BRepAlgoAPI_Cut(inner, body)
                names = carry(names, op)
                news.append(op.Shape())
    except Exception:
        raise KernelError("Kabuk oluşturulamadı (kalınlık çok büyük olabilir)")
    if not news or any(is_empty_shape(s) for s in news):
        raise KernelError("Kabuk oluşturulamadı (kalınlık çok büyük olabilir)")
    out = replace_bodies(part, targets, compound(news) if len(news) > 1 else news[0], names)
    name_new_faces(out.shape, out.names, "F%s:in" % f["fid"])
    return out


def feat_draft(part, f, upd):
    if part is None or part.empty():
        raise KernelError("Eğim verilecek gövde yok")
    ang = float(f.get("angle", 3.0))
    if not (0.0 < abs(ang) < 89.0):
        raise KernelError("Açı 0° ile 89° arasında olmalı")
    if not f.get("neutral"):
        raise KernelError("Tarafsız düzlem (yüz) seçilmedi")
    if not f.get("faces"):
        raise KernelError("Eğim verilecek yüz seçilmedi")
    ni, allf = resolve_face(part, f["neutral"])
    if ni < 0:
        raise KernelError("Tarafsız yüz bulunamadı")
    neutral = allf[ni]
    nn = face_normal_dir(neutral)
    if nn is None:
        raise KernelError("Tarafsız yüz düzlemsel olmalı")
    upd["neutral"] = face_ref_of(part, neutral, [float(v) for v in f["neutral"]["p"]])
    faces, refs = resolve_faces(part, f["faces"])
    upd["faces"] = refs
    # Çekme yönü: tarafsız yüzün içe bakan normali (parça bu yönde kalıptan çıkar)
    pull = [-v for v in nn] if not f.get("reverse", False) else nn
    pln = gp_Pln(gp_Pnt(*_face_point(neutral)), gp_Dir(*pull))
    bodies = solids_of(part.shape)
    targets = [b for b in bodies if any(any(fc.IsSame(x) for x in faces_of(b)) for fc in faces)]
    names, news = part.names, []
    for body in targets:
        bf = faces_of(body)
        mk = BRepOffsetAPI_DraftAngle(body)
        for fc in faces:
            if any(fc.IsSame(x) for x in bf):
                mk.Add(fc, gp_Dir(*pull), math.radians(ang), pln, True)
                if not mk.AddDone():
                    raise KernelError("Bu yüze eğim verilemez (düzlem, silindir veya koni olmalı)")
        mk.Build()
        if not mk.IsDone():
            raise KernelError("Eğim uygulanamadı")
        names = carry(names, mk)
        news.append(mk.Shape())
    out = replace_bodies(part, targets, compound(news) if len(news) > 1 else news[0], names)
    name_new_faces(out.shape, out.names, "F%s" % f["fid"])
    return out


def _norm2(v):
    ln = math.hypot(v[0], v[1])
    return [v[0] / ln, v[1] / ln] if ln > 1e-12 else [0.0, 0.0]


def _curve_ends(c):
    """Açık eğrinin uçları ve dışa doğru teğetleri (taslak 2B): [(nokta, yön), (nokta, yön)]."""
    t = c["t"]
    if t == "line":
        a, b = c["a"], c["b"]
        d = _norm2([b[0] - a[0], b[1] - a[1]])
        return [(a, [-d[0], -d[1]]), (b, d)]
    if t == "arc":
        p0, pm, p1 = c["p"]
        ax, ay, bx, by, cx, cy = p0[0], p0[1], pm[0], pm[1], p1[0], p1[1]
        dd = 2.0 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
        if abs(dd) < 1e-12:
            return []
        ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / dd
        uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / dd
        t0 = _norm2([-(p0[1] - uy), p0[0] - ux])
        if t0[0] * (pm[0] - p0[0]) + t0[1] * (pm[1] - p0[1]) < 0:
            t0 = [-t0[0], -t0[1]]
        t1 = _norm2([-(p1[1] - uy), p1[0] - ux])
        if t1[0] * (p1[0] - pm[0]) + t1[1] * (p1[1] - pm[1]) < 0:
            t1 = [-t1[0], -t1[1]]
        return [(p0, [-t0[0], -t0[1]]), (p1, t1)]
    if t == "bspline" and not c.get("closed", False) and len(c["p"]) >= 2:
        p = c["p"]
        return [(p[0], _norm2([p[0][0] - p[1][0], p[0][1] - p[1][1]])),
                (p[-1], _norm2([p[-1][0] - p[-2][0], p[-1][1] - p[-2][1]]))]
    return []


def _rib_extensions(shape, pl, curves):
    from OCP.IntCurvesFace import IntCurvesFace_ShapeIntersector
    from OCP.BRepClass3d import BRepClass3d_SolidClassifier
    from OCP.TopAbs import TopAbs_OUT
    from OCP.gp import gp_Lin
    ends = []
    for c in curves:
        ends.extend(_curve_ends(c))
    count = {}
    for p, _d in ends:
        key = (round(float(p[0]), 5), round(float(p[1]), 5))
        count[key] = count.get(key, 0) + 1
    si = IntCurvesFace_ShapeIntersector()
    si.Load(shape, 1e-7)
    out = []
    for ci, c in enumerate(curves):
        for ei, (p, d) in enumerate(_curve_ends(c)):
            if count[(round(float(p[0]), 5), round(float(p[1]), 5))] != 1 or d == [0.0, 0.0]:
                continue
            out.append((ci, ei, p, d))
    return out, si, (BRepClass3d_SolidClassifier, TopAbs_OUT, gp_Lin)


def _extend_rib_curves(shape, pl, curves):
    """Serbest uçları gövdeye değene kadar (+0,1 mm) uzatır. Çizgi uçlarında çizginin kendisi uzar
    (ayrı doğrusal parça LinearForm'u bozuyor); yay/spline uçlarına teğet doğru parçası eklenir."""
    free, si, (Classifier, OUT, Lin) = _rib_extensions(shape, pl, curves)
    out = [dict(c) for c in curves]
    extra = []
    for ci, ei, p, d in free:
        p3 = pl.pnt(p)
        d3 = [pl.x[k] * d[0] + pl.y[k] * d[1] for k in range(3)]
        length = 0.1
        if Classifier(shape, p3, 1e-7).State() == OUT:
            si.Perform(Lin(p3, gp_Dir(*d3)), 0.0, 1e9)
            ws = [si.WParameter(i) for i in range(1, si.NbPnt() + 1)] if si.IsDone() else []
            ws = [w for w in ws if w > 1e-9]
            if ws:
                length = min(ws) + 0.1
        q = [float(p[0]) + d[0] * length, float(p[1]) + d[1] * length]
        if out[ci]["t"] == "line":
            out[ci]["a" if ei == 0 else "b"] = q
        else:
            extra.append({"t": "line", "a": [float(p[0]), float(p[1])], "b": q, "k": "ext"})
    return out + extra


def feat_rib(part, f, upd):
    if part is None or part.empty():
        raise KernelError("Kaburganın dayanacağı gövde yok")
    t = float(f.get("t", 2.0))
    if t <= 0:
        raise KernelError("Kalınlık sıfırdan büyük olmalı")
    pl = Plane(f["plane"])
    pl, delta = _support_plane(part, f, pl, upd)
    curves = list(f.get("curves", []))
    if not curves:
        raise KernelError("Kaburga taslağında çizgi yok")

    def wire_of(cs):
        keys = EdgeKeys()
        edges = []
        for c in cs:
            edges.extend(keys.build(pl, c))
        mw = BRepBuilderAPI_MakeWire()
        mw.Add(lst(edges))
        if not mw.IsDone():
            raise KernelError("Kaburga profili tek bir bağlı zincir olmalı")
        return mw.Wire()

    def reversed_curve(c):
        r = dict(c)
        if c["t"] == "line":
            r["a"], r["b"] = c["b"], c["a"]
        elif c["t"] in ("arc", "bspline", "poly"):
            r["p"] = list(reversed(c["p"]))
        return r
    # Açık profilin serbest uçları teğet yönünde gövdeye değene kadar uzatılır;
    # LinearForm uç ile gövde arasında en küçük boşlukta bile başarısız olduğu için gereklidir.
    curves = _extend_rib_curves(part.shape, pl, curves)
    # Tel yönü geometriyle tersine çevrilir (yalnızca yönelim bayrağı LinearForm'u etkilemiyor)
    wires = [wire_of(curves), wire_of([reversed_curve(c) for c in reversed(curves)])]
    n = pl.n
    h = t * 0.5
    d1 = gp_Vec(n[0] * h, n[1] * h, n[2] * h)
    d2 = gp_Vec(-n[0] * h, -n[1] * h, -n[2] * h)
    v0 = volume_of(part.shape)
    # Malzemenin hangi tarafa dolacağını telin yönü belirler: iki yön de denenir, profil ile
    # gövde arasındaki küçük bölge (olağan kaburga) seçilir; "flip" diğerini seçer.
    tries = []
    for w in wires:
        try:
            form = BRepFeat_MakeLinearForm(part.shape, w, Geom_Plane(pl.pln()), d1, d2, 1, True)
            form.Perform()
        except Exception:
            continue
        if not form.IsDone() or is_empty_shape(form.Shape()):
            continue
        added = volume_of(form.Shape()) - v0
        if added > 1e-9:
            tries.append((added, form))
    if not tries:
        raise KernelError("Kaburga oluşturulamadı (profil gövdeye ulaşmıyor olabilir)")
    tries.sort(key=lambda x: x[0])
    form = tries[-1][1] if (f.get("flip", False) and len(tries) > 1) else tries[0][1]
    out = unify(Part(form.Shape(), carry(part.names, form)))
    name_new_faces(out.shape, out.names, "F%s" % f["fid"])
    return out


def feat_combine(part, f, upd):
    if part is None or part.empty():
        raise KernelError("Gövde yok")
    refs = f.get("bodies", [])
    if len(refs) < 2:
        raise KernelError("En az iki gövde seçin (ilki ana gövde)")
    idxs, new_refs = [], []
    bodies = solids_of(part.shape)
    for r in refs:
        i, bodies = resolve_body(part, r)
        if i in idxs:
            continue
        idxs.append(i)
        new_refs.append(body_ref_of(part, bodies[i], [float(v) for v in r["p"]]))
    upd["bodies"] = new_refs
    if len(idxs) < 2:
        raise KernelError("İki farklı gövde seçin")
    main = bodies[idxs[0]]
    tools = [bodies[i] for i in idxs[1:]]
    tool = tools[0] if len(tools) == 1 else compound(tools)
    op_name = f.get("op", "add")
    if op_name == "subtract":
        op = BRepAlgoAPI_Cut(main, tool)
    elif op_name == "common":
        op = BRepAlgoAPI_Common(main, tool)
    else:
        op = BRepAlgoAPI_Fuse(main, tool)
    if not op.IsDone():
        raise KernelError("Birleştirme başarısız")
    if is_empty_shape(op.Shape()):
        raise KernelError("Sonuç boş (gövdeler kesişmiyor olabilir)")
    out = replace_bodies(part, [main] + tools, op.Shape(), carry(part.names, op))
    return unify(out)


def _body_trsf(f):
    t = gp_Trsf()
    t.SetTranslation(gp_Vec(*[float(v) for v in f.get("t", [0, 0, 0])]))
    ang = float(f.get("angle", 0.0))
    if abs(ang) > 1e-12:
        r = gp_Trsf()
        r.SetRotation(gp_Ax1(gp_Pnt(*[float(v) for v in f.get("axis_o", [0, 0, 0])]),
                             gp_Dir(*[float(v) for v in f.get("axis_d", [0, 1, 0])])), math.radians(ang))
        t = t.Multiplied(r)
    return t


def feat_move_body(part, f, upd):
    if part is None or part.empty():
        raise KernelError("Gövde yok")
    if not f.get("body"):
        raise KernelError("Gövde seçilmedi")
    i, bodies = resolve_body(part, f["body"])
    body = bodies[i]
    upd["body"] = body_ref_of(part, body, [float(v) for v in f["body"]["p"]])
    tr = BRepBuilderAPI_Transform(body, _body_trsf(f), True)
    moved = tr.Shape()
    if f.get("copy", False):
        extra = NameMap()
        for g, n in carry(part.names, tr).items():
            if any(g.IsSame(x) for x in faces_of(moved)):
                extra.add(g, "%s@F%s" % (n, f["fid"]))
        rest = solids_of(part.shape)
        return Part(compound(rest + solids_of(moved)), part.names.merged(extra))
    return replace_bodies(part, [body], moved, carry(part.names, tr))


def feat_split(part, f, upd):
    if part is None or part.empty():
        raise KernelError("Bölünecek gövde yok")
    o = [float(v) for v in f["plane_o"]]
    n = [float(v) for v in f["plane_n"]]
    ln = math.sqrt(dot3(n, n))
    if ln < 1e-12:
        raise KernelError("Bölme düzlemi geçersiz")
    n = [v / ln for v in n]
    L = 4.0 * diag_of(part.shape) + abs(dot3(o, o)) ** 0.5
    big = BRepBuilderAPI_MakeFace(gp_Pln(gp_Pnt(*o), gp_Dir(*n)), -L, L, -L, L).Face()
    bodies = solids_of(part.shape)
    sp = BRepAlgoAPI_Splitter()
    sp.SetArguments(lst(bodies))
    sp.SetTools(lst([big]))
    sp.Build()
    if not sp.IsDone():
        raise KernelError("Bölme başarısız")
    pieces = solids_of(sp.Shape())
    if len(pieces) <= len(bodies):
        raise KernelError("Düzlem hiçbir gövdeyi kesmiyor")
    keep = f.get("keep", "both")
    out_solids = []
    for s in pieces:
        c = centroid_of(s)
        side = dot3([c[k] - o[k] for k in range(3)], n)
        if keep == "both" or (keep == "pos" and side > 0) or (keep == "neg" and side < 0):
            out_solids.append(s)
    if not out_solids:
        raise KernelError("Seçilen tarafta gövde kalmadı")
    out = Part(compound(out_solids), carry(part.names, sp))
    name_new_faces(out.shape, out.names, "F%s:cut" % f["fid"])
    return out


_import_cache = {}


def solidify(shape):
    """IGES gibi yüzey tabanlı içe aktarmalarda yüzleri dikip kapalı kabuklardan katı üretir."""
    if shape_list(shape, TopAbs_SOLID):
        return shape
    sew = BRepBuilderAPI_Sewing(1e-3)
    for f in shape_list(shape, TopAbs_FACE):
        sew.Add(f)
    sew.Perform()
    sewn = sew.SewedShape()
    solids = []
    for sh in shape_list(sewn, TopAbs_SHELL):
        ms = BRepBuilderAPI_MakeSolid(as_shell(sh))
        if ms.IsDone():
            fx = ShapeFix_Solid(ms.Solid())
            fx.Perform()
            solids.append(fx.Solid())
    if not solids:
        return sewn
    return solids[0] if len(solids) == 1 else compound(solids)


# ---------------------------------------------------------------- STL içe aktarma ve gövde dönüşümü (Faz 9+)

def read_stl_tris(path):
    """STL (ikili veya ASCII) → [(x1,y1,z1,x2,y2,z2,x3,y3,z3), ...]"""
    import struct
    data = open(path, "rb").read()
    if len(data) >= 84:
        n = struct.unpack("<I", data[80:84])[0]
        if 84 + n * 50 == len(data):
            out = []
            for i in range(n):
                o = 84 + i * 50 + 12
                out.append(struct.unpack("<9f", data[o:o + 36]))
            return out
    vs = []
    for line in data.decode("latin-1").splitlines():
        t = line.strip().split()
        if len(t) == 4 and t[0].lower() == "vertex":
            vs.extend(float(x) for x in t[1:])
    if len(vs) < 9:
        raise KernelError("STL okunamadı (üçgen yok)")
    return [tuple(vs[i:i + 9]) for i in range(0, len(vs) - len(vs) % 9, 9)]


def _taper_of(f, s):
    """Kademeli kesit büyütme: (eksen, a, b, [büyüme1, büyüme2] (ölçek öncesi mm), profil, kaydırma) ya da None.
    profil: [[x, c1, c2, boy1, boy2], ...] (özgün koordinat, eksene dik iki eksen sırasıyla)."""
    tp = f.get("taper") or {}
    prof = tp.get("profile") or []
    if not tp or len(prof) < 2:
        return None
    ax = {"x": 0, "y": 1, "z": 2}.get(str(tp.get("axis", "x")), 0)
    a, b = float(tp.get("a", 0.0)), float(tp.get("b", 0.0))
    if b - a <= 1e-9:
        raise KernelError("Kademeli büyütme bölgesi geçersiz (bitiş > başlangıç olmalı)")
    k1, k2 = (ax + 1) % 3, (ax + 2) % 3
    g = [float(v) for v in (tp.get("grow") or [0.0, 0.0])]
    sh = [float(v) for v in (tp.get("shift") or [0.0, 0.0])]
    prof = sorted([[float(v) for v in r] for r in prof])
    return (ax, a, b, [g[0] / s[k1], g[1] / s[k2]], prof, sh)


def _taper_point(p, tp):
    import bisect
    ax, a, b, g, prof, sh = tp
    u = p[ax]
    t = min(1.0, max(0.0, (u - a) / (b - a)))
    if t <= 0.0:
        return p
    xs = [r[0] for r in prof]
    i = bisect.bisect_left(xs, u)
    if i <= 0:
        r = prof[0]
    elif i >= len(prof):
        r = prof[-1]
    else:
        r0, r1 = prof[i - 1], prof[i]
        w = (u - r0[0]) / max(r1[0] - r0[0], 1e-12)
        r = [r0[j] + (r1[j] - r0[j]) * w for j in range(5)]
    p = list(p)
    for j, k in enumerate(((ax + 1) % 3, (ax + 2) % 3)):
        size = max(r[3 + j], 1e-6)
        c = r[1 + j] - sh[j]
        p[k] = c + (p[k] - c) * (1.0 + g[j] * t / size)
    return p


_AXES = {"x": 0, "y": 1, "z": 2}


def _stretch_of(f, s):
    """Bölgesel uzatma: tek bölge (sözlük) ya da bölge listesi → [(eksen, a, b, oran), ...] ya da None"""
    st = f.get("stretch") or {}
    regs = st if isinstance(st, list) else [st]
    out = []
    for r in regs:
        if not r or abs(float(r.get("add", 0.0))) <= 1e-12:
            continue
        ax = _AXES.get(str(r.get("axis", "x")), 0)
        a, b = float(r.get("a", 0.0)), float(r.get("b", 0.0))
        if b - a <= 1e-9:
            raise KernelError("Uzatma bölgesi geçersiz (bitiş > başlangıç olmalı)")
        out.append((ax, a, b, 1.0 + float(r["add"]) / s[ax] / (b - a)))
    return sorted(out) or None


def _band_at(rows, u):
    """Koruma bandı [alt, üst] — eksen konumuna göre doğrusal profil (uçlarda sabit)"""
    if len(rows) == 1 or u <= rows[0][0]:
        return rows[0][1], rows[0][2]
    if u >= rows[-1][0]:
        return rows[-1][1], rows[-1][2]
    for i in range(1, len(rows)):
        if u <= rows[i][0]:
            r0, r1 = rows[i - 1], rows[i]
            w = (u - r0[0]) / max(r1[0] - r0[0], 1e-12)
            return _lerp_inf(r0[1], r1[1], w), _lerp_inf(r0[2], r1[2], w)
    return rows[-1][1], rows[-1][2]


def _lerp_inf(a, b, w):
    """Doğrusal ara değer; sınırsız (±inf) uçlarda NaN üretmez"""
    if a == b:
        return a
    if not (math.isfinite(a) and math.isfinite(b)):
        return a if w < 0.5 else b
    return a + (b - a) * w


def _protect_of(f, s, o, t, stretch, taper):
    """Koruma bölgesi: eksen boyunca [a, b] aralığında, kesitteki bantların içi ölçeklenmeden yalnızca ötelenir.
    bant1 korunan katmanı seçer (ör. üst kısım: y ≥ y0); bant2 bu katmanın içindeki şerittir (ör. orta ±h) — katmanın
    dışında bant2 etkisizdir (bant1 geçiş payında kademeli), orası normal büyür. Böylece Jacobian üçgensel kalır, katlanma olmaz.
    protect {axis, a, b, blend (eksen boyunca geçiş, mm), bands [bant1, bant2] (eksene dik iki eksen sırasıyla;
    bant = [alt, üst] ya da [[konum, alt, üst], ...] profil; null/boş = eksenin tamamı; üst null = sınırsız),
    soft [2] (bant kenarındaki geçiş payı, özgün mm), offset [2] (korunan kısmın son ötelemesi, mm) ya da anchor [3]}"""
    pr = f.get("protect") or {}
    if not pr:
        return None
    ax = _AXES.get(str(pr.get("axis", "x")), 0)
    a, b = float(pr.get("a", 0.0)), float(pr.get("b", 0.0))
    if b - a <= 1e-9:
        raise KernelError("Koruma bölgesi geçersiz (bitiş > başlangıç olmalı)")
    ks = ((ax + 1) % 3, (ax + 2) % 3)
    inf = float("inf")
    bands = []
    raw = list(pr.get("bands") or [])
    for j in range(2):
        bd = raw[j] if j < len(raw) else None
        if not bd:
            bands.append(None)
            continue
        rows = bd if isinstance(bd[0], (list, tuple)) else [[a] + list(bd)]
        rows = sorted([[float(r[0]), -inf if r[1] is None else float(r[1]), inf if r[2] is None else float(r[2])] for r in rows])
        if any(r[2] < r[1] for r in rows):
            raise KernelError("Koruma bandı geçersiz (üst sınır alttan küçük)")
        bands.append(rows)
    soft = [max(float(v), 1e-6) for v in (list(pr.get("soft") or []) + [3.0, 3.0])[:2]]
    off = pr.get("offset")
    if off is None:
        anc = pr.get("anchor")
        if anc is None:
            anc = [0.0, 0.0, 0.0]
            anc[ax] = 0.5 * (a + b)
            for j, k in enumerate(ks):
                if bands[j] is None:
                    anc[k] = o[k]
                else:
                    lo, hi = _band_at(bands[j], anc[ax])
                    anc[k] = 0.5 * (lo + hi) if lo > -inf and hi < inf else (lo if lo > -inf else (hi if hi < inf else o[k]))
        anc = [float(v) for v in anc]
        q = _regular_point(anc, s, o, t, stretch, taper)
        off = [q[k] - anc[k] for k in ks]
    off = [float(v) for v in off]
    return (ax, a, b, max(float(pr.get("blend", 10.0)), 0.0), ks, bands, soft, off)


def body_xform(f):
    """İçe aktarma dönüşümü: (s[3], o[3], t[3], (uzatma, kademeli, koruma))"""
    sc = float(f.get("scale", 1.0))
    s = [sc * float(f.get(k, 1.0)) for k in ("sx", "sy", "sz")]
    o = [float(v) for v in (f.get("origin") or [0.0, 0.0, 0.0])]
    t = [float(v) for v in (f.get("move") or [0.0, 0.0, 0.0])]
    stretch = _stretch_of(f, s)
    taper = _taper_of(f, s)
    return s, o, t, (stretch, taper, _protect_of(f, s, o, t, stretch, taper))


def _regular_point(p, s, o, t, stretch, taper):
    p = list(p)
    if taper is not None:
        p = _taper_point(p, taper)
    if stretch:
        d = [0.0, 0.0, 0.0]
        for ax, a, b, k in stretch:
            u = p[ax]
            if u > b:
                d[ax] += (b - a) * (k - 1.0)
            elif u > a:
                d[ax] += (u - a) * (k - 1.0)
        p = [p[i] + d[i] for i in range(3)]
    return [o[i] + s[i] * (p[i] - o[i]) + t[i] for i in range(3)]


def xform_point(p, s, o, t, ex):
    stretch, taper, prot = ex
    q = _regular_point(p, s, o, t, stretch, taper)
    if prot is None:
        return q
    ax, a, b, bl, ks, bands, soft, off = prot
    u = float(p[ax])
    w = 1.0 if a <= u <= b else (max(0.0, 1.0 - (a - u if u < a else u - b) / bl) if bl > 0.0 else 0.0)
    if w <= 0.0:
        return q
    w = w * w * (3.0 - 2.0 * w)
    out = list(q)
    wl = 1.0       # katman ağırlığı: bant1'in içinde 1, geçişinde doğrusal azalır, dışında 0
    for j, k in enumerate(ks):
        lo, hi = (float("-inf"), float("inf")) if bands[j] is None else _band_at(bands[j], u)
        m = soft[j]
        c = float(p[k])
        if lo <= c <= hi:
            v = c + off[j]
        elif (c < lo and c <= lo - m) or (c > hi and c >= hi + m):
            v = q[k]
        else:
            e = lo - m if c < lo else hi + m      # geçiş payının dış kenarı: normal dönüşüm
            pe = list(p)
            pe[k] = e
            r = _regular_point(pe, s, o, t, stretch, taper)[k]
            edge = lo if c < lo else hi
            v = r + (edge + off[j] - r) * (c - e) / (edge - e)
        if j == 0:
            if lo <= c <= hi:
                wl = 1.0
            elif (c < lo and c <= lo - m) or (c > hi and c >= hi + m):
                wl = 0.0
            else:
                wl = (c - (lo - m)) / m if c < lo else (hi + m - c) / m
        else:
            v = q[k] + (v - q[k]) * wl         # şerit yalnızca katmanın içinde etkili
        out[k] = q[k] + (v - q[k]) * w
    return out


def kink_planes(ex):
    """Dönüşümün kırılma yüzeyleri (parça parça doğrusal sınırlar): (eksen k, bağlı eksen ya da -1, alfa, beta)
    düzlemi: p[k] = alfa + beta * p[bağlı eksen]. Ağ bu düzlemlerden kesilince her parçada dönüşüm doğrusal kalır."""
    stretch, taper, prot = ex
    pl = set()
    if stretch:
        for ax, a, b, _k in stretch:
            pl.add((ax, -1, a, 0.0))
            pl.add((ax, -1, b, 0.0))
    if taper is not None:
        ax, a, b, _g, prof, _sh = taper
        pl.add((ax, -1, a, 0.0))
        pl.add((ax, -1, b, 0.0))
        for r in prof:
            if a < r[0] < b:
                pl.add((ax, -1, r[0], 0.0))
    if prot is not None:
        ax, a, b, bl, ks, bands, soft, _off = prot
        for u in (a - bl, a, b, b + bl):
            pl.add((ax, -1, u, 0.0))
        for j, k in enumerate(ks):
            rows = bands[j]
            if rows is None:
                continue
            segs = [(rows[0], rows[0])] + list(zip(rows[:-1], rows[1:])) + [(rows[-1], rows[-1])]
            for r0, r1 in segs:
                if a - bl < r0[0] < b + bl:
                    pl.add((ax, -1, r0[0], 0.0))
                for col, dm in ((1, 0.0), (1, -soft[j]), (2, 0.0), (2, soft[j])):
                    v0, v1 = r0[col] + dm, r1[col] + dm
                    if not (math.isfinite(v0) and math.isfinite(v1)):
                        continue
                    du = r1[0] - r0[0]
                    be = (v1 - v0) / du if du > 1e-9 else 0.0
                    pl.add((k, ax if abs(be) > 1e-12 else -1, round(v0 - be * r0[0], 9), round(be, 12)))
    return sorted(pl)


def _cut_planes(verts, T, planes, snap=0.01):
    """Üçgen ağını düzlemlerle keser (kenar kesişim noktası kenara göre tek hesaplanır → ağ kapalı kalır).
    Düzleme snap'ten yakın köşeler düzlem üzerine kaydırılır (yalnızca k ekseninde)."""
    for k, ax, al, be in planes:
        d = [v[k] - al - (be * v[ax] if ax >= 0 else 0.0) for v in verts]
        for i, x in enumerate(d):
            if x != 0.0 and abs(x) < snap:     # düzleme çok yakın köşe düzleme oturtulur (ince şerit oluşmaz)
                v = list(verts[i])
                v[k] -= x
                verts[i] = tuple(v)
                d[i] = 0.0
        emap = {}
        NT = []
        for tri in T:
            da, db, dc = d[tri[0]], d[tri[1]], d[tri[2]]
            if min(da, db, dc) >= 0.0 or max(da, db, dc) <= 0.0:
                NT.append(tri)
                continue
            pos, neg = [], []
            for e in range(3):
                i, j = tri[e], tri[(e + 1) % 3]
                di, dj = d[i], d[j]
                if di >= 0.0:
                    pos.append(i)
                if di <= 0.0:
                    neg.append(i)
                if (di > 0.0 > dj) or (di < 0.0 < dj):
                    key = (i, j) if i < j else (j, i)
                    m = emap.get(key)
                    if m is None:
                        pa, pb = verts[key[0]], verts[key[1]]
                        t = d[key[0]] / (d[key[0]] - d[key[1]])
                        verts.append(tuple(pa[q] + (pb[q] - pa[q]) * t for q in range(3)))
                        d.append(0.0)
                        m = emap[key] = len(verts) - 1
                    pos.append(m)
                    neg.append(m)
            for poly in (pos, neg):
                for q in range(1, len(poly) - 1):
                    NT.append([poly[0], poly[q], poly[q + 1]])
        T = NT
    return T


def refine_xform(tris, fpt, tol=0.05, min_len=0.25, passes=12, src=None, planes=None):
    """Doğrusal olmayan dönüşüm için uyumlu (T-birleşimsiz) ağ inceltme: önce dönüşümün kırılma düzlemlerinden
    kesilir, sonra dönüşümün kenar boyunca doğrusal kalmadığı kenarlar (ara noktası tol'dan fazla sapan) ikiye
    bölünür; kenar kararı iki komşu üçgende aynı olduğundan ağ kapalı kalır.
    Dönüş: (dönüştürülmüş köşeler, üçgen köşe indisleri)."""
    verts, idx, T = [], {}, []
    for tr in tris:
        ids = []
        for k in range(3):
            key = tuple(tr[3 * k:3 * k + 3])
            i = idx.get(key)
            if i is None:
                i = idx[key] = len(verts)
                verts.append(key)
            ids.append(i)
        if ids[0] != ids[1] and ids[1] != ids[2] and ids[0] != ids[2]:
            T.append(ids)
    if planes:
        T = _cut_planes(verts, T, planes)
    img = [fpt(v) for v in verts]
    if tol <= 0.0:
        if src is not None:
            src.extend(verts)
        return img, T
    min2 = (2.0 * min_len) ** 2
    tol2 = tol * tol
    for _ in range(passes):
        mark = {}
        for tri in T:
            for e in ((tri[0], tri[1]), (tri[1], tri[2]), (tri[2], tri[0])):
                e = e if e[0] < e[1] else (e[1], e[0])
                if e in mark:
                    continue
                p, q = verts[e[0]], verts[e[1]]
                if sum((p[i] - q[i]) ** 2 for i in range(3)) < min2:
                    mark[e] = None
                    continue
                ip, iq = img[e[0]], img[e[1]]
                hit = None
                for sfr in (0.5, 0.25, 0.75):
                    m = [p[i] + (q[i] - p[i]) * sfr for i in range(3)]
                    fm = fpt(m)
                    if sum((fm[i] - ip[i] - (iq[i] - ip[i]) * sfr) ** 2 for i in range(3)) > tol2:
                        hit = (m, fm) if sfr == 0.5 else ([p[i] + (q[i] - p[i]) * 0.5 for i in range(3)], None)
                        break
                if hit is None:
                    mark[e] = None
                    continue
                m, fm = hit
                verts.append(tuple(m))
                img.append(fm if fm is not None else fpt(m))
                mark[e] = len(verts) - 1
        if not any(v is not None for v in mark.values()):
            break
        NT = []
        for a, b, c in T:
            mab = mark[(a, b) if a < b else (b, a)]
            mbc = mark[(b, c) if b < c else (c, b)]
            mca = mark[(c, a) if c < a else (a, c)]
            n = (mab is not None) + (mbc is not None) + (mca is not None)
            if n == 0:
                NT.append([a, b, c])
                continue
            # kanonik konum: ilk bölünen kenar a-b olacak şekilde döndür
            while mab is None or (n == 2 and mca is None):
                a, b, c = b, c, a
                mab, mbc, mca = mbc, mca, mab
            if n == 1:
                NT += [[a, mab, c], [mab, b, c]]
            elif n == 2:
                if mbc is not None:      # a-b ve b-c
                    NT += [[mab, b, mbc], [a, mab, mbc], [a, mbc, c]]
                else:                    # c-a ve a-b
                    NT += [[a, mab, mca], [mab, b, c], [mab, c, mca]]
            else:
                NT += [[a, mab, mca], [mab, b, mbc], [mca, mbc, c], [mab, mbc, mca]]
        T = NT
    if src is not None:
        src.extend(verts)
    return img, T


def import_stl_shape(path, f):
    import struct, tempfile
    s, o, t, stretch = body_xform(f)
    flip = s[0] * s[1] * s[2] < 0.0      # aynalama sarımı tersine çevirir
    raw = read_stl_tris(path)
    nonlin = any(e is not None for e in stretch)
    img, T = refine_xform(raw, lambda p: xform_point(p, s, o, t, stretch), float(f.get("refine", 0.05)) if nonlin else 0.0,
                          planes=kink_planes(stretch) if nonlin else None)
    buf = bytearray(b"DIY.CAD STL".ljust(80, b" "))
    buf += struct.pack("<I", len(T))
    for ia, ib, ic in T:
        a, b, c = img[ia], img[ib], img[ic]
        if flip:
            b, c = c, b
        buf += struct.pack("<12fH", 0.0, 0.0, 0.0, *a, *b, *c, 0)
    fd, tmp = tempfile.mkstemp(suffix=".stl")
    os.close(fd)
    try:
        with open(tmp, "wb") as fo:
            fo.write(bytes(buf))
        from OCP.StlAPI import StlAPI_Reader
        from OCP.TopoDS import TopoDS_Shape
        sh = TopoDS_Shape()
        if not StlAPI_Reader().Read(sh, tmp):
            raise KernelError("STL okunamadı")
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass
    if is_empty_shape(sh):
        raise KernelError("STL'de üçgen yok")
    return solidify(sh)


def feat_import(part, f, upd):
    path = str(f["path"])
    if not os.path.isfile(path):
        raise KernelError("Dosya bulunamadı: %s" % path)
    ext = os.path.splitext(path)[1].lower()
    if ext == ".stl":
        key = (path, os.path.getmtime(path), json.dumps({k: f.get(k) for k in ("scale", "sx", "sy", "sz", "origin", "move", "stretch", "taper", "protect", "refine")}, sort_keys=True))
        shape = _import_cache.get(key)
        if shape is None:
            shape = import_stl_shape(path, f)
            _import_cache.clear()
            _import_cache[key] = shape
        return _import_finish(part, f, shape)
    key = (path, os.path.getmtime(path))
    shape = _import_cache.get(key)
    if shape is None:
        rd = IGESControl_Reader() if ext in (".igs", ".iges") else STEPControl_Reader()
        if rd.ReadFile(path) != IFSelect_RetDone:
            raise KernelError("Dosya okunamadı")
        rd.TransferRoots()
        shape = rd.OneShape()
        if is_empty_shape(shape):
            raise KernelError("Dosyada katı/yüzey bulunamadı")
        fix = ShapeFix_Shape(shape)
        fix.Perform()
        shape = solidify(fix.Shape())
        _import_cache.clear()
        _import_cache[key] = shape
    s, o, t, stretch = body_xform(f)
    if any(e is not None for e in stretch):
        raise KernelError("Bölgesel uzatma / kademeli büyütme / koruma bölgesi yalnızca STL (ağ) gövdelerde desteklenir")
    if abs(s[0] - s[1]) > 1e-12 or abs(s[0] - s[2]) > 1e-12:
        from OCP.gp import gp_GTrsf, gp_Mat, gp_XYZ
        from OCP.BRepBuilderAPI import BRepBuilderAPI_GTransform
        g = gp_GTrsf()
        g.SetVectorialPart(gp_Mat(s[0], 0, 0, 0, s[1], 0, 0, 0, s[2]))
        g.SetTranslationPart(gp_XYZ(o[0] * (1 - s[0]) + t[0], o[1] * (1 - s[1]) + t[1], o[2] * (1 - s[2]) + t[2]))
        shape = BRepBuilderAPI_GTransform(shape, g, True).Shape()
    elif abs(s[0] - 1.0) > 1e-12 or any(abs(v) > 1e-12 for v in t):
        tr = gp_Trsf()
        if abs(s[0] - 1.0) > 1e-12:
            tr.SetScale(gp_Pnt(*o), s[0])
        if any(abs(v) > 1e-12 for v in t):
            mv = gp_Trsf()
            mv.SetTranslation(gp_Vec(*t))
            tr = mv.Multiplied(tr)
        shape = BRepBuilderAPI_Transform(shape, tr, True).Shape()
    return _import_finish(part, f, shape)


def _import_finish(part, f, shape):
    names = NameMap()
    for k, fc in enumerate(faces_of(shape)):
        names.add(fc, "F%s:i%d" % (f["fid"], k))
    tool = Part(shape, names)
    if part is None or part.empty():
        return tool
    try:
        return boolean(part, tool, False, True, f["fid"])
    except KernelError:
        return Part(compound([part.shape, shape]), part.names.merged(names))


# ---------------------------------------------------------------- Faz 5: süpürme, loft, çoğaltma, delik, kubbe

CUR_TOOLS = {}


def fuse_all(shapes, names=None):
    """Üst üste binebilen katıları tek geçerli katıda birleştirir (çok bağımsız değişkenli Boolean)."""
    if len(shapes) == 1:
        return shapes[0], names
    op = BRepAlgoAPI_Fuse()
    op.SetArguments(lst([shapes[0]]))
    op.SetTools(lst(shapes[1:]))
    op.Build()
    if not op.IsDone():
        raise KernelError("Birleştirme başarısız")
    return op.Shape(), (carry(names, op) if names is not None else None)


def _interp_wire(pts):
    arr = TColgp_HArray1OfPnt(1, len(pts))
    for i, q in enumerate(pts):
        arr.SetValue(i + 1, gp_Pnt(*q))
    it = GeomAPI_Interpolate(arr, False, 1e-7)
    it.Perform()
    if not it.IsDone():
        raise KernelError("Eğri oluşturulamadı")
    return BRepBuilderAPI_MakeWire(BRepBuilderAPI_MakeEdge(it.Curve()).Edge()).Wire()


def _helix_points(h, per_turn=24):
    """Spiral (düzlemsel) ve konik helis için örnek noktalar (aradeğerleme ile eğriye çevrilir)."""
    o, ax, x = [float(v) for v in h["o"]], [float(v) for v in h["axis"]], [float(v) for v in h["xdir"]]
    y = [ax[1] * x[2] - ax[2] * x[1], ax[2] * x[0] - ax[0] * x[2], ax[0] * x[1] - ax[1] * x[0]]
    r0, pitch, turns = float(h["r"]), float(h["pitch"]), float(h["turns"])
    sgn = 1.0 if h.get("ccw", True) else -1.0
    spiral = bool(h.get("spiral", False))
    tk = math.tan(math.radians(float(h.get("taper", 0.0))))
    n = max(8, int(turns * per_turn))
    out = []
    for i in range(n + 1):
        t = turns * i / float(n)
        a = 2.0 * math.pi * t * sgn
        if spiral:
            r, hz = r0 + pitch * t, 0.0
        else:
            r, hz = r0 + tk * pitch * t, pitch * t
        out.append([o[k] + (x[k] * math.cos(a) + y[k] * math.sin(a)) * r + ax[k] * hz for k in range(3)])
    return out


def _helix_wire(h):
    from OCP.Geom import Geom_CylindricalSurface
    from OCP.Geom2d import Geom2d_Line
    from OCP.gp import gp_Pnt2d, gp_Dir2d
    from OCP.BRepLib import BRepLib
    r = float(h["r"])
    pitch = float(h["pitch"])
    turns = float(h["turns"])
    if r <= 0 or abs(pitch) < 1e-9 or turns <= 0:
        raise KernelError("Helis ölçüleri geçersiz")
    if h.get("spiral", False) or abs(float(h.get("taper", 0.0))) > 1e-9:
        return _interp_wire(_helix_points(h))
    cyl = Geom_CylindricalSurface(gp_Ax3(gp_Pnt(*h["o"]), gp_Dir(*h["axis"]), gp_Dir(*h["xdir"])), r)
    du = 2.0 * math.pi * (1.0 if h.get("ccw", True) else -1.0)
    ln2 = Geom2d_Line(gp_Pnt2d(0.0, 0.0), gp_Dir2d(du, pitch))
    length = turns * math.sqrt((2.0 * math.pi) ** 2 + pitch ** 2)
    e = BRepBuilderAPI_MakeEdge(ln2, cyl, 0.0, length).Edge()
    BRepLib.BuildCurves3d_s(e)
    return BRepBuilderAPI_MakeWire(e).Wire()


def _path_wire(path):
    from OCP.GeomFill import GeomFill_IsFrenet, GeomFill_IsCorrectedFrenet
    kind = path.get("kind", "")
    if kind == "helix":
        return _helix_wire(path["helix"]), GeomFill_IsFrenet
    if kind == "sketch3d":
        edges = []
        for poly in path.get("polys", []):
            for i in range(len(poly) - 1):
                a, b = gp_Pnt(*poly[i]), gp_Pnt(*poly[i + 1])
                if a.Distance(b) > 1e-9:
                    edges.append(BRepBuilderAPI_MakeEdge(a, b).Edge())
        if not edges:
            raise KernelError("Yol (3B taslak) boş")
        mw = BRepBuilderAPI_MakeWire()
        mw.Add(lst(edges))
        if not mw.IsDone():
            raise KernelError("3B taslak yolu tek bir bağlı zincir olmalı")
        return mw.Wire(), GeomFill_IsCorrectedFrenet
    if kind == "sketch":
        pl = Plane(path["plane"])
        ws = _chain_wires(pl, path.get("chains", [])[:1], EdgeKeys())
        return ws[0][0], GeomFill_IsCorrectedFrenet
    if kind == "projcurve":
        w = CUR_CURVES.get(int(path.get("id", 0)))
        if w is None:
            raise KernelError("Projeksiyon eğrisi hesaplanamadı (önce o özelliği düzeltin)")
        return w, GeomFill_IsCorrectedFrenet
    raise KernelError("Eğri (yol) seçilmedi")


def feat_sweep(part, f, upd):
    pl = Plane(f["plane"])
    pl, delta = _support_plane(part, f, pl, upd)
    keys = EdgeKeys()
    faces = profile_faces(f, pl, keys)
    fid = f["fid"]
    spine, mode = _path_wire(f.get("path", {}))
    solids, names = [], NameMap()
    guide = f.get("guide")
    twist = float(f.get("twist", 0.0))
    if guide or abs(twist) > 1e-9:
        from OCP.BRepTools import BRepTools
        for face in faces:
            if guide:
                from OCP.BRepFill import BRepFill_ContactOnBorder
                gw, _m = _path_wire(guide)
                ps = BRepOffsetAPI_MakePipeShell(spine)
                ps.SetMode(gw, True, BRepFill_ContactOnBorder)
                ps.Add(BRepTools.OuterWire_s(face), False, False)
                try:
                    ps.Build()
                    ps.MakeSolid()
                except Exception:
                    raise KernelError("Kılavuzlu süpürme oluşturulamadı (kılavuz profile değmeli)")
                if not ps.IsDone():
                    raise KernelError("Kılavuzlu süpürme oluşturulamadı (kılavuz profile değmeli)")
                sol = ps.Shape()
            else:
                sol = _twist_sweep(face, spine, twist)
            if volume_of(sol) < 0:
                sol = sol.Reversed()
            solids.append(sol)
        tool = Part(solids[0] if len(solids) == 1 else compound(solids), names)
        name_new_faces(tool.shape, tool.names, "F%s" % fid)
        cut = bool(f.get("cut", False))
        upd["_tool"] = (tool, cut)
        return boolean(part, tool, cut, bool(f.get("merge", True)), fid)
    for face in faces:
        mp = BRepOffsetAPI_MakePipe(spine, face, mode, False)
        mp.Build()
        if not mp.IsDone() or is_empty_shape(mp.Shape()):
            raise KernelError("Süpürme oluşturulamadı (profil yolun başında olmalı)")
        ck = cap_key(face, keys)
        for e in edges_of(face):
            k = keys.key_of(e)
            for g in mp.Generated(e):
                names.add(g, "F%s:s:%s" % (fid, k if k is not None else "?"))
        try:
            names.add(mp.FirstShape(), "F%s:a:%s" % (fid, ck))
            names.add(mp.LastShape(), "F%s:b:%s" % (fid, ck))
        except Exception:
            pass
        sol = mp.Shape()
        if volume_of(sol) < 0:
            sol = sol.Reversed()
        solids.append(sol)
    tool = Part(solids[0] if len(solids) == 1 else compound(solids), names)
    name_new_faces(tool.shape, tool.names, "F%s" % fid)
    cut = bool(f.get("cut", False))
    upd["_tool"] = (tool, cut)
    return boolean(part, tool, cut, bool(f.get("merge", True)), fid)


def _twist_sweep(face, spine, twist_deg):
    """Bükmeli süpürme: profil yol boyunca taşınır (paralel taşıma çerçevesi) ve teğet etrafında
    doğrusal olarak döndürülür; ara kesitlerden yumuşak loft kurulur. Delikler ayrı loft olarak çıkarılır."""
    from OCP.BRepAdaptor import BRepAdaptor_CompCurve
    from OCP.GCPnts import GCPnts_AbscissaPoint
    from OCP.BRepOffsetAPI import BRepOffsetAPI_ThruSections
    from OCP.BRepTools import BRepTools
    cc = BRepAdaptor_CompCurve(spine)
    L = GCPnts_AbscissaPoint.Length_s(cc)
    if L < 1e-9:
        raise KernelError("Yol çok kısa")
    n = int(max(12, min(96, abs(twist_deg) / 7.5 + 8)))
    u0 = cc.FirstParameter()
    P, T = [], []
    for k in range(n + 1):
        u = u0 if k == 0 else GCPnts_AbscissaPoint(cc, L * k / n, u0).Parameter()
        pp = gp_Pnt()
        vv = gp_Vec()
        cc.D1(u, pp, vv)
        ln = vv.Magnitude()
        P.append(vec3(pp))
        T.append([vv.X() / ln, vv.Y() / ln, vv.Z() / ln])

    def rot(v, axis, ang):
        c, sn = math.cos(ang), math.sin(ang)
        d = dot3(axis, v)
        cr = [axis[1] * v[2] - axis[2] * v[1], axis[2] * v[0] - axis[0] * v[2], axis[0] * v[1] - axis[1] * v[0]]
        return [v[i] * c + cr[i] * sn + axis[i] * d * (1 - c) for i in range(3)]

    def norm(v):
        ln2 = math.sqrt(dot3(v, v)) or 1.0
        return [x / ln2 for x in v]
    sa = BRepAdaptor_Surface(face)
    if sa.GetType() == GeomAbs_Plane:
        xd = sa.Plane().XAxis().Direction()
        N = [xd.X(), xd.Y(), xd.Z()]
    else:
        N = [1.0, 0.0, 0.0]
    N = norm([N[i] - T[0][i] * dot3(N, T[0]) for i in range(3)])
    ax0 = gp_Ax3(gp_Pnt(*P[0]), gp_Dir(*T[0]), gp_Dir(*N))
    frames = [ax0]
    Nk = N
    for k in range(1, n + 1):
        a = T[k - 1]
        b = T[k]
        cr = [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
        sn = math.sqrt(dot3(cr, cr))
        if sn > 1e-12:
            Nk = rot(Nk, [c / sn for c in cr], math.atan2(sn, dot3(a, b)))
        Nt = rot(Nk, b, math.radians(twist_deg) * k / n)
        Nt = norm([Nt[i] - b[i] * dot3(Nt, b) for i in range(3)])
        frames.append(gp_Ax3(gp_Pnt(*P[k]), gp_Dir(*b), gp_Dir(*Nt)))
    outer = BRepTools.OuterWire_s(face)
    loops = [outer] + [as_wire(w) for w in shape_list(face, TopAbs_WIRE) if not as_wire(w).IsSame(outer)]
    solids = []
    for lw in loops:
        ts = BRepOffsetAPI_ThruSections(True, False)
        for fr in frames:
            tr = gp_Trsf()
            tr.SetDisplacement(ax0, fr)
            ts.AddWire(as_wire(BRepBuilderAPI_Transform(lw, tr, True).Shape()))
        try:
            ts.Build()
        except Exception:
            raise KernelError("Bükmeli süpürme oluşturulamadı")
        if not ts.IsDone():
            raise KernelError("Bükmeli süpürme oluşturulamadı")
        sh = ts.Shape()
        if volume_of(sh) < 0:
            sh = sh.Reversed()
        solids.append(sh)
    out = solids[0]
    for hole in solids[1:]:
        out = BRepAlgoAPI_Cut(out, hole).Shape()
    return out


def feat_loft(part, f, upd):
    from OCP.BRepOffsetAPI import BRepOffsetAPI_ThruSections
    secs = f.get("sections", [])
    if len(secs) < 2:
        raise KernelError("En az iki profil taslağı seçin")
    fid = f["fid"]
    wires = []
    for sec in secs:
        pl = Plane(sec["plane"])
        edges = []
        keys = EdgeKeys()
        for c in sec["curves"]:
            edges.extend(keys.build(pl, c))
        if not edges:
            raise KernelError("Profil taslağında kapalı kontur yok")
        wires.append(make_wire(edges))
    if f.get("guide"):
        # Kılavuz eğrili loft: kesitler kılavuz eğrisi (omurga) boyunca boru kabuğuyla birleştirilir
        gw, _m = _path_wire(f["guide"])
        ps = BRepOffsetAPI_MakePipeShell(gw)
        for w in wires:
            ps.Add(w, False, False)
        try:
            ps.Build()
            ps.MakeSolid()
        except Exception:
            raise KernelError("Kılavuz eğrili loft oluşturulamadı (kılavuz her profilden geçmeli)")
        if not ps.IsDone() or is_empty_shape(ps.Shape()):
            raise KernelError("Kılavuz eğrili loft oluşturulamadı (kılavuz her profilden geçmeli)")
        sol = ps.Shape()
        if volume_of(sol) < 0:
            sol = sol.Reversed()
        tool = Part(sol, NameMap())
        name_new_faces(tool.shape, tool.names, "F%s" % fid)
        cut = bool(f.get("cut", False))
        upd["_tool"] = (tool, cut)
        return boolean(part, tool, cut, bool(f.get("merge", True)), fid)
    ts = BRepOffsetAPI_ThruSections(True, bool(f.get("ruled", False)))
    for w in wires:
        ts.AddWire(w)
    try:
        ts.Build()
    except Exception:
        raise KernelError("Loft oluşturulamadı")
    if not ts.IsDone() or is_empty_shape(ts.Shape()):
        raise KernelError("Loft oluşturulamadı (profiller uyumsuz olabilir)")
    sol = ts.Shape()
    if volume_of(sol) < 0:
        sol = sol.Reversed()
    tool = Part(sol, NameMap())
    name_new_faces(tool.shape, tool.names, "F%s" % fid)
    cut = bool(f.get("cut", False))
    upd["_tool"] = (tool, cut)
    return boolean(part, tool, cut, bool(f.get("merge", True)), fid)


def _pattern_trsfs(f, ref=None):
    t = f["type"]
    out = []
    if t == "lpattern":
        d1 = [float(v) for v in f["dir1"]]
        n1 = max(1, int(f.get("count1", 2)))
        s1 = float(f.get("spacing1", 10.0))
        d2 = [float(v) for v in f.get("dir2", [0, 0, 0])]
        n2 = max(1, int(f.get("count2", 1))) if f.get("use2", False) else 1
        s2 = float(f.get("spacing2", 10.0))
        for i in range(n1):
            for j in range(n2):
                if i == 0 and j == 0:
                    continue
                out.append(trsf_translate([d1[k] * s1 * i + d2[k] * s2 * j for k in range(3)]))
    elif t == "cpattern":
        n = max(1, int(f.get("count", 4)))
        total = float(f.get("angle", 360.0))
        step = total / n if (f.get("equal", True) and abs(total - 360.0) < 1e-9) else (total / max(n - 1, 1))
        ax = gp_Ax1(gp_Pnt(*f["axis_o"]), gp_Dir(*f["axis_d"]))
        for i in range(1, n):
            tr = gp_Trsf()
            tr.SetRotation(ax, math.radians(step * i))
            out.append(tr)
    elif t == "mirror":
        tr = gp_Trsf()
        tr.SetMirror(gp_Ax2(gp_Pnt(*f["plane_o"]), gp_Dir(*f["plane_n"])))
        out.append(tr)
    elif t == "tpattern":
        for o in f.get("offsets", []):
            out.append(trsf_translate([float(v) for v in o]))
    elif t == "cvpattern":
        from OCP.BRepAdaptor import BRepAdaptor_CompCurve
        from OCP.GCPnts import GCPnts_AbscissaPoint
        w, _m = _path_wire(f.get("curve", {}))
        cc = BRepAdaptor_CompCurve(w)
        L = GCPnts_AbscissaPoint.Length_s(cc)
        n = max(1, int(f.get("count", 3)))
        closed = BRep_Tool.IsClosed_s(w)
        if f.get("equal", True):
            step = L / n if closed else L / max(n - 1, 1)
        else:
            step = float(f.get("spacing", 10.0))
        u0 = cc.FirstParameter()
        # Eğrinin çoğaltılan özelliğe yakın ucu başlangıç kabul edilir (izdüşüm vb. yönü çevirebilir)
        rev = False
        if ref is not None and not closed:
            pa, pb = vec3(cc.Value(cc.FirstParameter())), vec3(cc.Value(cc.LastParameter()))
            rev = math.dist(ref, pb) < math.dist(ref, pa)

        def at(sv):
            sv = min(max(sv, 0.0), L)
            if rev:
                sv = L - sv
            uu = u0 if sv <= 0.0 else GCPnts_AbscissaPoint(cc, sv, u0).Parameter()
            pp, vv = gp_Pnt(), gp_Vec()
            cc.D1(uu, pp, vv)
            if rev:
                vv.Reverse()
            return pp, vv
        p0, v0 = at(0.0)
        t0 = [v0.X(), v0.Y(), v0.Z()]
        ln0 = math.sqrt(dot3(t0, t0)) or 1.0
        t0 = [x / ln0 for x in t0]
        for k in range(1, n):
            sk = step * k
            if sk > L + 1e-7:
                break
            pk, vk = at(sk)
            tr = trsf_translate([pk.X() - p0.X(), pk.Y() - p0.Y(), pk.Z() - p0.Z()])
            if f.get("align", True):
                tk = [vk.X(), vk.Y(), vk.Z()]
                lk = math.sqrt(dot3(tk, tk)) or 1.0
                tk = [x / lk for x in tk]
                cr = [t0[1] * tk[2] - t0[2] * tk[1], t0[2] * tk[0] - t0[0] * tk[2], t0[0] * tk[1] - t0[1] * tk[0]]
                sn = math.sqrt(dot3(cr, cr))
                if sn > 1e-12:
                    rt = gp_Trsf()
                    rt.SetRotation(gp_Ax1(p0, gp_Dir(*cr)), math.atan2(sn, dot3(t0, tk)))
                    tr = tr.Multiplied(rt)
            out.append(tr)
    if not out:
        raise KernelError("Çoğaltma örneği yok (sayıyı kontrol edin)")
    return out


def _transform_part(tool, tr, suffix):
    mk = BRepBuilderAPI_Transform(tool.shape, tr, True)
    names = NameMap()
    for g, n in carry(tool.names, mk).items():
        names.add(g, n + suffix)
    return Part(mk.Shape(), names)


def feat_pattern(part, f, upd):
    if part is None or part.empty():
        raise KernelError("Çoğaltılacak gövde yok")
    fid = f["fid"]
    ref = None
    if f["type"] == "cvpattern":
        seeds = [CUR_TOOLS[int(x)][0].shape for x in f.get("features", []) if int(x) in CUR_TOOLS]
        try:
            ref = centroid_of(seeds[0]) if seeds else centroid_of(part.shape)
        except Exception:
            ref = None
    trsfs = _pattern_trsfs(f, ref)
    if f.get("bodies", False) or not f.get("features"):
        copies = []
        names = NameMap()
        base = Part(compound(solids_of(part.shape)), part.names)
        for k, tr in enumerate(trsfs):
            cp = _transform_part(base, tr, "@F%s.%d" % (fid, k + 1))
            copies.extend(solids_of(cp.shape))
            names = names.merged(cp.names)
        out = boolean(part, Part(compound(copies), names), False, True, fid)
        name_new_faces(out.shape, out.names, "F%s" % fid)
        return out
    for sf in f.get("features", []):
        tt = CUR_TOOLS.get(int(sf))
        if tt is None:
            raise KernelError("Çoğaltılan özellik bulunamadı veya çoğaltılamaz (yalnızca ekstrüzyon, döndürme, süpürme, loft, delik)")
        tool, cut = tt
        copies, names = [], NameMap()
        for k, tr in enumerate(trsfs):
            cp = _transform_part(tool, tr, "@F%s.%d" % (fid, k + 1))
            copies.append(cp.shape)
            names = names.merged(cp.names)
        merged, names = fuse_all(copies, names)
        part = boolean(part, Part(merged, names), cut, True, fid)
    name_new_faces(part.shape, part.names, "F%s" % fid)
    return part


def feat_hole(part, f, upd):
    from OCP.BRepPrimAPI import BRepPrimAPI_MakeCylinder, BRepPrimAPI_MakeCone
    if part is None or part.empty():
        raise KernelError("Delik açılacak gövde yok")
    if not f.get("face"):
        raise KernelError("Delik yüzü seçilmedi")
    pts = f.get("points", [])
    if not pts:
        raise KernelError("Delik konumu seçilmedi (yüze tıklayın)")
    i, faces = resolve_face(part, f["face"])
    if i < 0:
        raise KernelError("Delik yüzü bulunamadı")
    face = faces[i]
    n = face_normal_dir(face)
    if n is None:
        raise KernelError("Delik yüzü düzlemsel olmalı")
    upd["face"] = face_ref_of(part, face, [float(v) for v in f["face"]["p"]])
    fp = _face_point(face)
    diag = diag_of(part.shape)
    d = float(f["d"])
    r = d * 0.5
    through = f.get("end", "through") == "through"
    depth = 4.0 * diag + 10.0 if through else float(f.get("depth", 10.0))
    eps = 0.01
    down = [-v for v in n]
    holes = []
    new_pts = []
    for p in pts:
        pieces = []
        p = [float(v) for v in p]
        dist = dot3([p[k] - fp[k] for k in range(3)], n)
        q = [p[k] - n[k] * dist for k in range(3)]
        new_pts.append(q)
        top = [q[k] + n[k] * eps for k in range(3)]
        pieces.append(BRepPrimAPI_MakeCylinder(gp_Ax2(gp_Pnt(*top), gp_Dir(*down)), r, depth + eps).Shape())
        if not through and float(f.get("point_ang", 118.0)) > 0:
            ha = math.radians(float(f.get("point_ang", 118.0)) * 0.5)
            bot = [q[k] - n[k] * depth for k in range(3)]
            pieces.append(BRepPrimAPI_MakeCone(gp_Ax2(gp_Pnt(*bot), gp_Dir(*down)), r, 0.0, r / math.tan(ha)).Shape())
        ht = f.get("htype", "simple")
        if ht == "cbore":
            pieces.append(BRepPrimAPI_MakeCylinder(gp_Ax2(gp_Pnt(*top), gp_Dir(*down)), float(f["cb_d"]) * 0.5,
                                                   float(f["cb_h"]) + eps).Shape())
        elif ht == "csink":
            ca = math.radians(float(f.get("cs_ang", 90.0)) * 0.5)
            rc = float(f["cs_d"]) * 0.5
            h = (rc - r) / math.tan(ca)
            if h > 1e-9:
                pieces.append(BRepPrimAPI_MakeCone(gp_Ax2(gp_Pnt(*top), gp_Dir(*down)), rc + eps * math.tan(ca), r,
                                                   h + eps).Shape())
        holes.append(fuse_all(pieces)[0])
    upd["points"] = new_pts
    tool = Part(fuse_all(holes)[0], NameMap())
    upd["_tool"] = (tool, True)
    out = boolean(part, tool, True, True, f["fid"])
    name_new_faces(out.shape, out.names, "F%s:h" % f["fid"])
    return out


def feat_dome(part, f, upd):
    from OCP.BRepOffsetAPI import BRepOffsetAPI_ThruSections
    from OCP.BRepTools import BRepTools
    if part is None or part.empty():
        raise KernelError("Kubbe için gövde yok")
    if not f.get("face"):
        raise KernelError("Kubbe yüzü seçilmedi")
    i, faces = resolve_face(part, f["face"])
    if i < 0:
        raise KernelError("Kubbe yüzü bulunamadı")
    face = faces[i]
    n = face_normal_dir(face)
    if n is None:
        raise KernelError("Kubbe yüzü düzlemsel olmalı")
    upd["face"] = face_ref_of(part, face, [float(v) for v in f["face"]["p"]])
    h = float(f.get("height", 5.0))
    if h <= 0:
        raise KernelError("Yükseklik sıfırdan büyük olmalı")
    props = GProp_GProps()
    BRepGProp.SurfaceProperties_s(face, props)
    c = vec3(props.CentreOfMass())
    outer = BRepTools.OuterWire_s(face)
    ts = BRepOffsetAPI_ThruSections(True, False)
    ts.AddWire(outer)
    N = 10
    for k in range(1, N):
        th = (k / float(N)) * math.pi * 0.5
        sc = gp_Trsf()
        sc.SetScale(gp_Pnt(*c), math.cos(th))
        mv = trsf_translate([n[j] * h * math.sin(th) for j in range(3)])
        w = BRepBuilderAPI_Transform(outer, mv.Multiplied(sc), True).Shape()
        ts.AddWire(as_wire(w))
    ts.AddVertex(BRepBuilderAPI_MakeVertex(gp_Pnt(*[c[j] + n[j] * h for j in range(3)])).Vertex())
    try:
        ts.Build()
    except Exception:
        raise KernelError("Kubbe oluşturulamadı")
    if not ts.IsDone():
        raise KernelError("Kubbe oluşturulamadı")
    sol = ts.Shape()
    if volume_of(sol) < 0:
        sol = sol.Reversed()
    out = boolean(part, Part(sol, NameMap()), False, True, f["fid"])
    name_new_faces(out.shape, out.names, "F%s" % f["fid"])
    return out


CUR_CURVES = {}


def _wire_polys(w, defl=0.05):
    out = []
    for e in edges_of(w):
        c = BRepAdaptor_Curve(e)
        try:
            dis = GCPnts_QuasiUniformDeflection(c, defl)
            pts = [vec3(dis.Value(k)) for k in range(1, dis.NbPoints() + 1)] if dis.IsDone() else []
        except Exception:
            pts = []
        if len(pts) < 2:
            pts = [vec3(c.Value(c.FirstParameter())), vec3(c.Value(c.LastParameter()))]
        out.append(pts)
    return out


def feat_projcurve(part, f, upd):
    """Taslak eğrisini taslak normali doğrultusunda bir yüze izdüşürür (3B eğri; süpürme yolu/kılavuz olur)."""
    from OCP.BRepProj import BRepProj_Projection
    if part is None or part.empty():
        raise KernelError("İzdüşürülecek gövde yok")
    if not f.get("face"):
        raise KernelError("Hedef yüz seçilmedi")
    i, faces = resolve_face(part, f["face"])
    if i < 0:
        raise KernelError("Hedef yüz bulunamadı")
    face = faces[i]
    upd["face"] = face_ref_of(part, face, [float(v) for v in f["face"]["p"]])
    pl = Plane(f["plane"])
    ws = _chain_wires(pl, f.get("chains", []), EdgeKeys())
    best, bd = None, 1e30
    for w, _closed in ws[:1]:
        pr = BRepProj_Projection(w, face, gp_Dir(*pl.n))
        while pr.More():
            c = pr.Current()
            d = shape_dist(c, w)
            if d < bd:
                best, bd = c, d
            pr.Next()
    if best is None:
        raise KernelError("Eğri yüze düşmüyor (izdüşüm boş)")
    w2 = as_wire(best)
    CUR_CURVES[int(f["fid"])] = w2
    upd["_curve"] = w2
    upd["poly"] = _wire_polys(w2)
    return part


def _cyl_frame(face, pl):
    s = BRepAdaptor_Surface(face)
    if s.GetType() != GeomAbs_Cylinder:
        raise KernelError("Sarma için silindirik bir yüz seçin")
    cy = s.Cylinder()
    ax = cy.Axis()
    d = [ax.Direction().X(), ax.Direction().Y(), ax.Direction().Z()]
    o = vec3(ax.Location())
    if abs(dot3(d, pl.n)) > 1e-6:
        raise KernelError("Taslak düzlemi silindir eksenine paralel olmalı")
    v = [pl.o[k] - o[k] for k in range(3)]
    x = [v[k] - d[k] * dot3(v, d) for k in range(3)]
    ln = math.sqrt(dot3(x, x))
    if ln < 1e-9:
        x = list(pl.n)
    else:
        x = [c / ln for c in x]
    y = [d[1] * x[2] - d[2] * x[1], d[2] * x[0] - d[0] * x[2], d[0] * x[1] - d[1] * x[0]]
    return o, d, x, y, cy.Radius()


def _wrap_face(face_cyl, pl, loops):
    """Taslak konturlarını silindir yüzeyine sarar: düzlemdeki (w, v) koordinatları yüzey
    parametresine (u = w / R, v) eşlenir — yay uzunluğu korunur (açılabilir yüzey)."""
    from OCP.Geom import Geom_CylindricalSurface
    from OCP.Geom2d import Geom2d_Line
    from OCP.Geom2dAPI import Geom2dAPI_Interpolate
    from OCP.gp import gp_Pnt2d, gp_Dir2d
    from OCP.BRepLib import BRepLib
    try:
        from OCP.TColgp import TColgp_HArray1OfPnt2d
    except ImportError:
        from OCP.collections import HArray1_gp_Pnt2d as TColgp_HArray1OfPnt2d
    o, d, x, y, R = _cyl_frame(face_cyl, pl)
    surf = Geom_CylindricalSurface(gp_Ax3(gp_Pnt(*o), gp_Dir(*d), gp_Dir(*x)), R)

    def uv(p):
        q = [p[k] - o[k] for k in range(3)]
        return (dot3(q, y) / R, dot3(q, d))

    def loop_wire(curves):
        edges = []
        for c in curves:
            for e in curve_edges(pl, c):
                ca = BRepAdaptor_Curve(e)
                a3, b3 = vec3(ca.Value(ca.FirstParameter())), vec3(ca.Value(ca.LastParameter()))
                if c["t"] == "line" or c["t"] == "poly":
                    a, b = uv(a3), uv(b3)
                    L2 = math.hypot(b[0] - a[0], b[1] - a[1])
                    if L2 < 1e-12:
                        continue
                    ln2 = Geom2d_Line(gp_Pnt2d(*a), gp_Dir2d(b[0] - a[0], b[1] - a[1]))
                    edges.append(BRepBuilderAPI_MakeEdge(ln2, surf, 0.0, L2).Edge())
                elif c["t"] in ("circle", "arc"):
                    # Düzlemdeki daire (u = w/R, v) uzayında tam bir elipstir: u yönünde r/R, v yönünde r.
                    # Kapalı daire iki yarım kenara bölünür (tek kenarlı periyodik kontur kalınlaştırmayı bozuyor).
                    from OCP.Geom2d import Geom2d_Ellipse
                    from OCP.gp import gp_Elips2d, gp_Ax22d
                    cc3 = ca.Circle()
                    r = cc3.Radius()
                    cu, cv = uv(vec3(cc3.Location()))
                    a_v, b_u = r, r / R
                    if a_v >= b_u:
                        el = gp_Elips2d(gp_Ax22d(gp_Pnt2d(cu, cv), gp_Dir2d(0.0, 1.0), gp_Dir2d(-1.0, 0.0)), a_v, b_u)
                        th = lambda q: math.atan2(-(q[0] - cu) / b_u, (q[1] - cv) / a_v)
                    else:
                        el = gp_Elips2d(gp_Ax22d(gp_Pnt2d(cu, cv), gp_Dir2d(1.0, 0.0), gp_Dir2d(0.0, 1.0)), b_u, a_v)
                        th = lambda q: math.atan2((q[1] - cv) / a_v, (q[0] - cu) / b_u)
                    g2 = Geom2d_Ellipse(el)
                    if c["t"] == "circle":
                        t0 = th(uv(a3))
                        edges.append(BRepBuilderAPI_MakeEdge(g2, surf, t0, t0 + math.pi).Edge())
                        edges.append(BRepBuilderAPI_MakeEdge(g2, surf, t0 + math.pi, t0 + 2.0 * math.pi).Edge())
                    else:
                        p0, pm, p1 = (uv(pl.w(q)) for q in c["p"])
                        ccw = (pm[0] - p0[0]) * (p1[1] - pm[1]) - (pm[1] - p0[1]) * (p1[0] - pm[0]) > 0
                        s0, s1 = (th(p0), th(p1)) if ccw else (th(p1), th(p0))
                        while s1 <= s0:
                            s1 += 2.0 * math.pi
                        edges.append(BRepBuilderAPI_MakeEdge(g2, surf, s0, s1).Edge())
                else:
                    # Diğer eğriler: periyodik olmayan aradeğerleme, kapalıysa iki parçaya bölünür
                    closed = math.dist(a3, b3) < 1e-9
                    u0, u1 = ca.FirstParameter(), ca.LastParameter()
                    spans = [(u0, (u0 + u1) * 0.5), ((u0 + u1) * 0.5, u1)] if closed else [(u0, u1)]
                    for sa, sb in spans:
                        n = 64
                        pts = [uv(vec3(ca.Value(sa + (sb - sa) * k / n))) for k in range(n + 1)]
                        arr = TColgp_HArray1OfPnt2d(1, len(pts))
                        for k, q in enumerate(pts):
                            arr.SetValue(k + 1, gp_Pnt2d(*q))
                        it = Geom2dAPI_Interpolate(arr, False, 1e-9)
                        it.Perform()
                        if not it.IsDone():
                            raise KernelError("Sarma eğrisi oluşturulamadı")
                        edges.append(BRepBuilderAPI_MakeEdge(it.Curve(), surf).Edge())
        mw = BRepBuilderAPI_MakeWire()
        mw.Add(lst(edges))
        if not mw.IsDone():
            raise KernelError("Sarılan kontur birleştirilemedi")
        w = mw.Wire()
        BRepLib.BuildCurves3d_s(w)
        return w
    faces = []
    for i, L in enumerate(loops):
        if int(L["depth"]) % 2 != 0:
            continue
        mf = BRepBuilderAPI_MakeFace(surf, loop_wire(L["curves"]), True)
        for H in loops:
            if int(H.get("parent", -1)) == i and int(H["depth"]) % 2 == 1:
                mf.Add(loop_wire(H["curves"]))
        if not mf.IsDone():
            raise KernelError("Sarılan yüz oluşturulamadı")
        fc = mf.Face()
        BRepLib.BuildCurves3d_s(fc)
        sf = ShapeFix_Face(fc)
        sf.FixOrientation()
        sf.Perform()
        faces.append(as_face(sf.Face()))
    if not faces:
        raise KernelError("Taslakta kapalı kontur yok")
    return faces


def feat_wrap(part, f, upd):
    if part is None or part.empty():
        raise KernelError("Sarma için gövde yok")
    if not f.get("face"):
        raise KernelError("Silindirik yüz seçilmedi")
    i, faces = resolve_face(part, f["face"])
    if i < 0:
        raise KernelError("Silindirik yüz bulunamadı")
    face = faces[i]
    upd["face"] = face_ref_of(part, face, [float(v) for v in f["face"]["p"]])
    pl = Plane(f["plane"])
    wfaces = _wrap_face(face, pl, f.get("loops", []))
    wt = f.get("wtype", "emboss")
    if wt == "scribe":
        sp = BRepAlgoAPI_Splitter()
        sp.SetArguments(lst([part.shape]))
        sp.SetTools(lst(wfaces))
        sp.Build()
        if not sp.IsDone():
            raise KernelError("Çizgi sarma başarısız")
        out = Part(sp.Shape(), carry(part.names, sp))
        name_new_faces(out.shape, out.names, "F%s" % f["fid"])
        return out
    depth = float(f.get("depth", 1.0))
    if depth <= 0:
        raise KernelError("Derinlik sıfırdan büyük olmalı")
    # Silindir yüzeyinin normali eksenden dışa bakar: kabartma dışa, oyma içe kalınlaştırılır
    solids = []
    for wf in wfaces:
        mk = BRepOffsetAPI_MakeThickSolid()
        mk.MakeThickSolidBySimple(wf, depth if wt == "emboss" else -depth)
        mk.Build()
        if not mk.IsDone():
            raise KernelError("Sarma kalınlığı oluşturulamadı")
        sh = mk.Shape()
        if volume_of(sh) < 0:
            sh = sh.Reversed()
        solids.append(sh)
    tool = Part(fuse_all(solids)[0], NameMap())
    out = boolean(part, tool, wt != "emboss", True, f["fid"])
    name_new_faces(out.shape, out.names, "F%s" % f["fid"])
    return out


def feat_emboss(part, f, upd):
    """Kabartma/gravür: profil, taslak normali doğrultusunda gövdenin karşılaştığı yüzeylere
    sabit kalınlıkta (yüzeyi izleyerek) eklenir veya oyulur."""
    from OCP.IntCurvesFace import IntCurvesFace_ShapeIntersector
    from OCP.gp import gp_Lin
    if part is None or part.empty():
        raise KernelError("Kabartma için gövde yok")
    h = float(f.get("depth", 1.0))
    if h <= 0:
        raise KernelError("Yükseklik sıfırdan büyük olmalı")
    pl = Plane(f["plane"])
    keys = EdgeKeys()
    pfaces = profile_faces(f, pl, keys)
    dsgn = 1.0 if f.get("reverse", False) else -1.0
    dn = [pl.n[k] * dsgn for k in range(3)]
    diag = diag_of(part.shape)
    L = 4.0 * diag + 10.0 + abs(dot3([pl.o[k] for k in range(3)], dn))
    prism = fuse_all([BRepPrimAPI_MakePrism(fc, gp_Vec(*[dn[k] * L for k in range(3)]), False, True).Shape() for fc in pfaces])[0]
    deboss = f.get("etype", "emboss") == "deboss"
    mo = BRepOffsetAPI_MakeOffsetShape()
    mo.PerformByJoin(part.shape, -h if deboss else h, 1e-4)
    if not mo.IsDone():
        raise KernelError("Gövde ofseti oluşturulamadı (kalınlık çok büyük olabilir)")
    osh = mo.Shape()
    sols = solids_of(osh)
    if not sols:
        shells = shape_list(osh, TopAbs_SHELL)
        if not shells:
            raise KernelError("Gövde ofseti oluşturulamadı")
        sols = [BRepBuilderAPI_MakeSolid(as_shell(shells[0])).Solid()]
    off = sols[0] if len(sols) == 1 else compound(sols)
    if volume_of(off) < 0:
        off = off.Reversed()
    layer = BRepAlgoAPI_Cut(part.shape, off).Shape() if deboss else BRepAlgoAPI_Cut(off, part.shape).Shape()
    region = BRepAlgoAPI_Common(prism, layer).Shape()
    comps = solids_of(region)
    if not comps:
        raise KernelError("Profil gövdenin üzerine düşmüyor")
    # Yalnızca taslaktan bakınca ilk karşılaşılan katman (arka yüzlerdeki parçalar atılır)
    si_b = IntCurvesFace_ShapeIntersector()
    si_b.Load(part.shape, 1e-7)
    keep = []
    for comp in comps:
        c = centroid_of(comp)
        t = dot3([c[k] - pl.o[k] for k in range(3)], dn)
        start = [c[k] - dn[k] * t for k in range(3)]
        si_b.Perform(gp_Lin(gp_Pnt(*start), gp_Dir(*dn)), -1e-6, 1e9)
        tb = min([si_b.WParameter(i) for i in range(1, si_b.NbPnt() + 1)], default=1e30)
        si_c = IntCurvesFace_ShapeIntersector()
        si_c.Load(comp, 1e-7)
        si_c.Perform(gp_Lin(gp_Pnt(*start), gp_Dir(*dn)), -1e-6, 1e9)
        tc = min([si_c.WParameter(i) for i in range(1, si_c.NbPnt() + 1)], default=1e30)
        if tc <= tb + 1e-4:
            keep.append(comp)
    if not keep:
        raise KernelError("Profil gövdenin üzerine düşmüyor")
    tool = Part(keep[0] if len(keep) == 1 else compound(keep), NameMap())
    out = boolean(part, tool, deboss, True, f["fid"])
    name_new_faces(out.shape, out.names, "F%s" % f["fid"])
    return out


# ---------------------------------------------------------------- Faz 6: teknik resim (gizli çizgi kaldırma)

def _proj2(p, x, yv):
    return [dot3(p, x), dot3(p, yv)]


def _edges_2d(comp, defl):
    """HLR sonucundaki (z=0 görünüş düzlemindeki) kenarları 2B çoklu çizgilere çevirir; daireleri ayrıca bildirir."""
    polys, circles = [], []
    if comp is None or comp.IsNull():
        return polys, circles
    for e in edges_of(comp):
        c = BRepAdaptor_Curve(e)
        t = c.GetType()
        u0, u1 = c.FirstParameter(), c.LastParameter()
        if t == GeomAbs_Line:
            pts = [vec3(c.Value(u0)), vec3(c.Value(u1))]
        else:
            try:
                dis = GCPnts_QuasiUniformDeflection(c, defl)
                pts = [vec3(dis.Value(k)) for k in range(1, dis.NbPoints() + 1)] if dis.IsDone() else []
            except Exception:
                pts = []
            if len(pts) < 2:
                pts = [vec3(c.Value(u0)), vec3(c.Value(u1))]
        polys.append([[q[0], q[1]] for q in pts])
        if t == GeomAbs_Circle:
            ci = c.Circle()
            lc = ci.Location()
            circles.append({"c": [lc.X(), lc.Y()], "r": ci.Radius(), "full": abs((u1 - u0) - 2.0 * math.pi) < 1e-6})
    return polys, circles


def _wire_poly(w, face, x, yv, defl):
    from OCP.BRepTools import BRepTools_WireExplorer
    from OCP.TopAbs import TopAbs_REVERSED as REV
    pts = []
    ex = BRepTools_WireExplorer(w, face)
    while ex.More():
        e = ex.Current()
        c = BRepAdaptor_Curve(e)
        u0, u1 = c.FirstParameter(), c.LastParameter()
        if c.GetType() == GeomAbs_Line:
            seg = [vec3(c.Value(u0)), vec3(c.Value(u1))]
        else:
            n = max(8, int(abs(u1 - u0) / max(defl, 1e-3) * 2.0)) if c.GetType() != GeomAbs_Circle else max(12, int(48 * abs(u1 - u0) / (2.0 * math.pi)))
            seg = [vec3(c.Value(u0 + (u1 - u0) * k / n)) for k in range(n + 1)]
        if e.Orientation() == REV:
            seg.reverse()
        for q in seg:
            q2 = _proj2(q, x, yv)
            if not pts or math.dist(pts[-1], q2) > 1e-9:
                pts.append(q2)
        ex.Next()
    if len(pts) > 2 and math.dist(pts[0], pts[-1]) < 1e-9:
        pts.pop()
    return pts


def _suppress_covered(polys, cover, tol, curve_tol=None):
    """Teknik resim önceliği: `cover` (görünür) çizgileriyle çakışan kısımları `polys`'tan çıkarır.
    Her parça için, aynı doğru üzerindeki örtücü parçaların kapladığı aralıklar düşülür."""
    if not polys or not cover:
        return polys
    # Örtücü parçalar için ızgara dizini
    segs = []
    for pl in cover:
        for i in range(1, len(pl)):
            segs.append((pl[i - 1][0], pl[i - 1][1], pl[i][0], pl[i][1]))
    if not segs:
        return polys
    xs = [s[0] for s in segs] + [s[2] for s in segs]
    ys = [s[1] for s in segs] + [s[3] for s in segs]
    cell = max(max(xs) - min(xs), max(ys) - min(ys), 1e-6) / 64.0
    grid = {}
    for k, (ax, ay, bx, by) in enumerate(segs):
        for gx in range(int(math.floor((min(ax, bx) - tol) / cell)), int(math.floor((max(ax, bx) + tol) / cell)) + 1):
            for gy in range(int(math.floor((min(ay, by) - tol) / cell)), int(math.floor((max(ay, by) + tol) / cell)) + 1):
                grid.setdefault((gx, gy), []).append(k)

    def covered(ax, ay, bx, by):
        dx, dy = bx - ax, by - ay
        L = math.hypot(dx, dy)
        if L < 1e-12:
            return [(0.0, 1.0)]
        ux, uy = dx / L, dy / L
        cand = set()
        for gx in range(int(math.floor((min(ax, bx) - tol) / cell)), int(math.floor((max(ax, bx) + tol) / cell)) + 1):
            for gy in range(int(math.floor((min(ay, by) - tol) / cell)), int(math.floor((max(ay, by) + tol) / cell)) + 1):
                cand.update(grid.get((gx, gy), ()))
        iv = []
        for k in cand:
            px, py, qx, qy = segs[k]
            # Örtücü parçanın iki ucu da bu doğruya yakın olmalı (eşdoğrusal)
            d1 = abs((px - ax) * uy - (py - ay) * ux)
            d2 = abs((qx - ax) * uy - (qy - ay) * ux)
            if d1 > tol or d2 > tol:
                continue
            t1 = ((px - ax) * ux + (py - ay) * uy) / L
            t2 = ((qx - ax) * ux + (qy - ay) * uy) / L
            lo, hi = max(0.0, min(t1, t2) - tol / L), min(1.0, max(t1, t2) + tol / L)
            if hi > lo:
                iv.append((lo, hi))
        iv.sort()
        merged = []
        for lo, hi in iv:
            if merged and lo <= merged[-1][1]:
                merged[-1] = (merged[-1][0], max(merged[-1][1], hi))
            else:
                merged.append((lo, hi))
        return merged

    def near_cover(px, py, r):
        gx, gy = int(math.floor(px / cell)), int(math.floor(py / cell))
        rr = int(math.ceil(r / cell))
        for ix in range(gx - rr, gx + rr + 1):
            for iy in range(gy - rr, gy + rr + 1):
                for k in grid.get((ix, iy), ()):
                    ax, ay, bx, by = segs[k]
                    dx, dy = bx - ax, by - ay
                    l2 = dx * dx + dy * dy
                    t = 0.0 if l2 < 1e-24 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
                    if math.hypot(ax + dx * t - px, ay + dy * t - py) <= r:
                        return True
        return False

    out = []
    for pl in polys:
        cur = []
        curved = curve_tol is not None and len(pl) > 2
        for i in range(1, len(pl)):
            a, b = pl[i - 1], pl[i]
            cov = covered(a[0], a[1], b[0], b[1])
            if curved and not (len(cov) == 1 and cov[0][0] <= 1e-9 and cov[0][1] >= 1.0 - 1e-9):
                # Eğri parçaları farklı ayrıklaştırılmış olabilir: uçlar ve orta nokta örtücüye yakınsa kaplı say
                m = [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5]
                if all(near_cover(q[0], q[1], curve_tol) for q in (a, b, m)):
                    cov = [(0.0, 1.0)]
            # Kaplanmayan aralıklar
            free, t = [], 0.0
            for lo, hi in cov:
                if lo > t:
                    free.append((t, lo))
                t = max(t, hi)
            if t < 1.0:
                free.append((t, 1.0))
            L = math.hypot(b[0] - a[0], b[1] - a[1])
            free = [(lo, hi) for lo, hi in free if (hi - lo) * L > tol * 4]
            for j, (lo, hi) in enumerate(free):
                p0 = [a[0] + (b[0] - a[0]) * lo, a[1] + (b[1] - a[1]) * lo]
                p1 = [a[0] + (b[0] - a[0]) * hi, a[1] + (b[1] - a[1]) * hi]
                if cur and lo < 1e-9 and math.hypot(cur[-1][0] - p0[0], cur[-1][1] - p0[1]) < 1e-9:
                    cur.append(p1)
                else:
                    if len(cur) >= 2:
                        out.append(cur)
                    cur = [p0, p1]
                if hi < 1.0 - 1e-9:
                    if len(cur) >= 2:
                        out.append(cur)
                    cur = []
            if not free:
                if len(cur) >= 2:
                    out.append(cur)
                cur = []
        if len(cur) >= 2:
            out.append(cur)
    return out


def cmd_hlr(req):
    """Görünüşler: {id, dir (izleyiciye doğru), x (görünüşün sağı), section?: {o, n}} →
    görünür / gizli / teğet kenarlar (görünüş koordinatlarında, mm), daireler ve kesit tarama bölgeleri."""
    from OCP.HLRBRep import HLRBRep_Algo, HLRBRep_HLRToShape
    from OCP.HLRAlgo import HLRAlgo_Projector
    from OCP.BRepPrimAPI import BRepPrimAPI_MakeHalfSpace
    if req.get("comps"):
        # Montaj resmi: saklanan parçaların dönüşümlü bileşiği
        shapes = [sh for sh in _asm_shapes(req) if sh is not None]
        if not shapes:
            return {"ok": False, "error": "Montajda katı yok"}
        shape0 = TopoDS_Compound()
        bld = BRep_Builder()
        bld.MakeCompound(shape0)
        for sh in shapes:
            bld.Add(shape0, sh)
    else:
        part = ST.part
        if part is None or part.empty():
            return {"ok": False, "error": "Modelde katı yok"}
        shape0 = part.shape
    diag = diag_of(shape0)
    defl = max(0.005, diag * 0.0005)
    views = []
    for v in req.get("views", []):
        d = [float(t) for t in v["dir"]]
        x = [float(t) for t in v["x"]]
        yv = [d[1] * x[2] - d[2] * x[1], d[2] * x[0] - d[0] * x[2], d[0] * x[1] - d[1] * x[0]]
        out = {"id": v["id"], "hatch": []}
        try:
            sh = shape0
            sec = v.get("section")
            if sec:
                o = [float(t) for t in sec["o"]]
                n = [float(t) for t in sec["n"]]
                L = 4.0 * diag + 100.0 + math.sqrt(dot3(o, o))
                face = BRepBuilderAPI_MakeFace(gp_Pln(gp_Pnt(*o), gp_Dir(*n)), -L, L, -L, L).Face()
                hs = BRepPrimAPI_MakeHalfSpace(face, gp_Pnt(*[o[k] + n[k] * L * 0.5 for k in range(3)])).Solid()
                sh = BRepAlgoAPI_Cut(shape0, hs).Shape()
                if is_empty_shape(sh):
                    raise KernelError("Kesit düzlemi gövdeyi kesmiyor")
                for fc in faces_of(sh):
                    fnd = face_normal_dir(fc)
                    if fnd is None or abs(dot3(fnd, n)) < 0.999999:
                        continue
                    fp = _face_point(fc)
                    if abs(dot3([fp[k] - o[k] for k in range(3)], n)) > 1e-6:
                        continue
                    loops = [_wire_poly(as_wire(w), fc, x, yv, defl) for w in shape_list(fc, TopAbs_WIRE)]
                    out["hatch"].append([lp for lp in loops if len(lp) >= 3])
            algo = HLRBRep_Algo()
            algo.Add(sh)
            algo.Projector(HLRAlgo_Projector(gp_Ax2(gp_Pnt(0, 0, 0), gp_Dir(*d), gp_Dir(*x))))
            algo.Update()
            algo.Hide()
            h = HLRBRep_HLRToShape(algo)
            vis, circ = _edges_2d(h.VCompound(), defl)
            vo, circ2 = _edges_2d(h.OutLineVCompound(), defl)
            hid, _c = _edges_2d(h.HCompound(), defl)
            ho, _c2 = _edges_2d(h.OutLineHCompound(), defl)
            tg, _c3 = _edges_2d(h.Rg1LineVCompound(), defl)
            tgh, _c4 = _edges_2d(h.Rg1LineHCompound(), defl)
            visible = vis + vo
            tol = max(1e-4, diag * 1e-6)
            out.update({"visible": visible, "hidden": _suppress_covered(hid + ho, visible, tol, defl * 2.0 + tol),
                        "tangent": _suppress_covered(tg, visible, tol, defl * 2.0 + tol), "tangent_hidden": tgh,
                        "circles": circ + circ2})
        except KernelError as exc:
            out["error"] = str(exc)
        except Exception as exc:
            out["error"] = "Görünüş hesaplanamadı: %s" % (str(exc) or type(exc).__name__)
        views.append(out)
    return {"ok": True, "views": views}


# ---------------------------------------------------------------- ağ ve bilgi çıktısı

SURF_TYPES = {GeomAbs_Plane: "plane", GeomAbs_Cylinder: "cylinder", GeomAbs_Cone: "cone",
              GeomAbs_Sphere: "sphere", GeomAbs_Torus: "torus", GeomAbs_BSplineSurface: "bspline",
              GeomAbs_BezierSurface: "bezier", GeomAbs_SurfaceOfRevolution: "revolution",
              GeomAbs_SurfaceOfExtrusion: "extrusion"}
CURVE_TYPES = {GeomAbs_Line: "line", GeomAbs_Circle: "circle", GeomAbs_Ellipse: "ellipse"}


def face_info(face, idx):
    s = BRepAdaptor_Surface(face)
    st = s.GetType()
    info = {"id": idx, "type": SURF_TYPES.get(st, "other")}
    rev = face.Orientation() == TopAbs_REVERSED
    if st == GeomAbs_Plane:
        ax = s.Plane().Axis()
        d = ax.Direction()
        n = [d.X(), d.Y(), d.Z()]
        info["n"] = [-v for v in n] if rev else n
        info["p"] = _face_point(face)
    elif st == GeomAbs_Cylinder:
        cy = s.Cylinder()
        ax = cy.Axis()
        info["axis"] = [ax.Direction().X(), ax.Direction().Y(), ax.Direction().Z()]
        info["o"] = vec3(ax.Location())
        info["r"] = cy.Radius()
    elif st == GeomAbs_Cone:
        co = s.Cone()
        ax = co.Axis()
        info["axis"] = [ax.Direction().X(), ax.Direction().Y(), ax.Direction().Z()]
        info["o"] = vec3(ax.Location())
        info["angle"] = math.degrees(co.SemiAngle())
    elif st == GeomAbs_Sphere:
        sp = s.Sphere()
        info["o"] = vec3(sp.Location())
        info["r"] = sp.Radius()
    props = GProp_GProps()
    BRepGProp.SurfaceProperties_s(face, props)
    info["area"] = props.Mass()
    return info


def mesh_shape(part, lin, ang):
    shape = part.shape
    BRepMesh_IncrementalMesh(shape, lin, False, ang, True)
    fmap = TopTools_IndexedMapOfShape()
    TopExp.MapShapes_s(shape, TopAbs_FACE, fmap)
    body_of = {}
    for bi, b in enumerate(solids_of(shape)):
        for fc in faces_of(b):
            body_of[fmap.FindIndex(fc) - 1] = bi
    pos = array.array("f")
    fid = array.array("i")
    faces = []
    for i in range(1, fmap.Extent() + 1):
        face = as_face(fmap.FindKey(i))
        info = face_info(face, i - 1)
        info["name"] = part.names.get(face) or ""
        info["body"] = body_of.get(i - 1, -1)
        faces.append(info)
        loc = TopLoc_Location()
        tri = BRep_Tool.Triangulation_s(face, loc)
        if tri is None:
            continue
        trsf = loc.Transformation()
        nodes = []
        for k in range(1, tri.NbNodes() + 1):
            p = tri.Node(k).Transformed(trsf)
            nodes.append((p.X(), p.Y(), p.Z()))
        rev = face.Orientation() == TopAbs_REVERSED
        for k in range(1, tri.NbTriangles() + 1):
            a, b, c = tri.Triangle(k).Get()
            if rev:
                b, c = c, b
            pos.extend(nodes[a - 1])
            pos.extend(nodes[b - 1])
            pos.extend(nodes[c - 1])
            fid.append(i - 1)
    # Kenarlar (dikiş ve dejenere kenarlar hariç)
    anc = edge_face_map(shape)
    edges = []
    for i in range(1, anc.Extent() + 1):
        e = as_edge(anc.FindKey(i))
        if BRep_Tool.Degenerated_s(e):
            continue
        fl = anc.FindFromIndex(i)
        fids = []
        seam = False
        for fsh in fl:
            fi = fmap.FindIndex(fsh) - 1
            if fi in fids:
                seam = True
            elif fi >= 0:
                fids.append(fi)
            if BRep_Tool.IsClosed_s(e, as_face(fsh)):
                seam = True
        if seam and len(fids) <= 1:
            continue
        c = BRepAdaptor_Curve(e)
        try:
            dis = GCPnts_QuasiUniformDeflection(c, lin * 0.5)
            pts = [vec3(dis.Value(k)) for k in range(1, dis.NbPoints() + 1)] if dis.IsDone() else []
        except Exception:
            pts = []
        if len(pts) < 2:
            pts = [vec3(c.Value(c.FirstParameter())), vec3(c.Value(c.LastParameter()))]
        flat = [v for p in pts for v in p]
        sig = edge_signature(e)
        info = {"id": len(edges), "pts": b64f(flat), "f": fids, "m": sig["m"], "d": sig["d"],
                "type": CURVE_TYPES.get(c.GetType(), "other"), "len": _edge_length(e),
                "fn": edge_name(part, e, anc)}
        info["closed"] = TopExp.FirstVertex_s(e).IsSame(TopExp.LastVertex_s(e))
        if c.GetType() == GeomAbs_Circle:
            ci = c.Circle()
            ad = ci.Axis().Direction()
            info["r"] = ci.Radius()
            info["o"] = vec3(ci.Location())
            info["n"] = [ad.X(), ad.Y(), ad.Z()]
        elif c.GetType() == GeomAbs_Ellipse:
            el = c.Ellipse()
            ad = el.Axis().Direction()
            xd = el.XAxis().Direction()
            info["o"] = vec3(el.Location())
            info["r"] = el.MajorRadius()
            info["r2"] = el.MinorRadius()
            info["n"] = [ad.X(), ad.Y(), ad.Z()]
            info["xd"] = [xd.X(), xd.Y(), xd.Z()]
        edges.append(info)
        for fi in fids:
            faces[fi].setdefault("e", []).append(info["id"])
    return {"pos": b64f(pos), "face": b64i(fid), "tris": len(fid)}, faces, edges


def _edge_length(e):
    props = GProp_GProps()
    BRepGProp.LinearProperties_s(e, props)
    return props.Mass()


def mass_of(shape):
    solids = solids_of(shape)
    if not solids:
        if not surfaces_of(shape):
            return None
        # Yalnız yüzey gövdeleri: hacim 0, alan = yüzey alanı
        sp0 = GProp_GProps()
        BRepGProp.SurfaceProperties_s(shape, sp0)
        return {"volume": 0.0, "area": sp0.Mass(), "center": vec3(sp0.CentreOfMass()),
                "tensor": [[0.0] * 3 for _ in range(3)], "solids": 0, "bodies": []}
    if surfaces_of(shape):
        shape = compound(solids)  # açık yüzey gövdeleri hacme/alana katılmaz
    vp = GProp_GProps()
    BRepGProp.VolumeProperties_s(shape, vp)
    sp = GProp_GProps()
    BRepGProp.SurfaceProperties_s(shape, sp)
    c = vp.CentreOfMass()
    m = vp.MatrixOfInertia()
    tensor = [[m.Value(i, j) for j in (1, 2, 3)] for i in (1, 2, 3)]
    return {"volume": vp.Mass(), "area": sp.Mass(), "center": vec3(c), "tensor": tensor,
            "solids": len(solids), "bodies": [volume_of(s) for s in solids]}


# ---------------------------------------------------------------- Faz 8: sac metal ve kaynaklı konstrüksiyon

def _prism_faces(it, fid, key, names, keys=None):
    """Bir öğenin profil yüzlerini vektör boyunca uzatır; yan yüzler F<fid>:s:<key>.<k> adlarını alır."""
    pl = Plane(it["plane"])
    keys = keys or EdgeKeys()
    faces = faces_from_loops(pl, it["loops"], keys)
    vec = gp_Vec(*[float(v) for v in it["vec"]])
    if vec.Magnitude() < 1e-9:
        raise KernelError("Uzatma boyu sıfır")
    out = []
    for face in faces:
        pr = BRepPrimAPI_MakePrism(face, vec)
        if not pr.IsDone():
            raise KernelError("Prizma oluşturulamadı")
        if names is not None:
            for e in edges_of(face):
                k = keys.key_of(e)
                for g in pr.Generated(e):
                    names.add(g, "F%s:s:%s.%s" % (fid, key, k if k is not None else "?"))
            names.add(pr.FirstShape(), "F%s:a:%s" % (fid, key))
            names.add(pr.LastShape(), "F%s:b:%s" % (fid, key))
        out.append(pr.Shape())
    return out


def feat_prisms(part, f, upd):
    fid = f["fid"]
    names = NameMap()
    shapes = []
    for i, it in enumerate(f.get("items", [])):
        shapes += _prism_faces(it, fid, str(it.get("key", i)), names)
    if not shapes:
        raise KernelError("Geometri boş")
    acc = shapes[0]
    for sh in shapes[1:]:
        op = BRepAlgoAPI_Fuse(acc, sh)
        tmp = carry(names, op)
        names.d = tmp.d
        acc = op.Shape()
    tool = Part(acc, names)
    name_new_faces(tool.shape, tool.names, "F%s" % fid)
    upd["_tool"] = (tool, False)
    return boolean(part, tool, False, bool(f.get("merge", True)), fid)


def _halfspace_cut(sh, o, n, size):
    """sh'den (x - o)·n > 0 tarafını çıkarır."""
    from OCP.BRepPrimAPI import BRepPrimAPI_MakeHalfSpace
    L = size
    face = BRepBuilderAPI_MakeFace(gp_Pln(gp_Pnt(*o), gp_Dir(*n)), -L, L, -L, L).Face()
    hs = BRepPrimAPI_MakeHalfSpace(face, gp_Pnt(*[o[k] + n[k] * L * 0.5 for k in range(3)])).Solid()
    return BRepAlgoAPI_Cut(sh, hs).Shape()


def feat_weldment(part, f, upd):
    fid = f["fid"]
    members = f.get("members", [])
    if not members:
        raise KernelError("Üye yok")
    raw, env = [], []
    for i, m in enumerate(members):
        shp = _prism_faces(m, fid, "w%d" % i, None)
        raw.append(shp[0] if len(shp) == 1 else compound(shp))
        e = dict(m)
        e["loops"] = m.get("env", m["loops"])
        env.append(_prism_faces(e, fid, "e%d" % i, None)[0])
    size = 10.0
    for sh in raw:
        size = max(size, diag_of(sh) * 4.0)
    solids = []
    for i, m in enumerate(members):
        sh = raw[i]
        for c in m.get("cuts", []):
            sh = _halfspace_cut(sh, [float(v) for v in c["o"]], [float(v) for v in c["n"]], size)
        for j in m.get("trim_by", []):
            sh = BRepAlgoAPI_Cut(sh, env[int(j)]).Shape()
        if is_empty_shape(sh):
            raise KernelError("Üye %d kırpma sonrası boş kaldı" % (i + 1))
        solids.extend(solids_of(sh) or [sh])
    names = NameMap()
    tool = Part(compound(solids), names)
    name_new_faces(tool.shape, tool.names, "F%s" % fid)
    upd["_tool"] = (tool, False)
    return boolean(part, tool, False, False, fid)


# ---------------------------------------------------------------- Faz 8: yüzey modelleme

def _add_surfaces(part, tool):
    if part is None or part.empty():
        return tool
    return Part(compound(solids_of(part.shape) + surfaces_of(part.shape) + [tool.shape]), part.names.merged(tool.names))


def _surf_tool(shapes, names, fid):
    tool = Part(shapes[0] if len(shapes) == 1 else compound(shapes), names)
    name_new_faces(tool.shape, tool.names, "F%s" % fid)
    return tool


def feat_srf_extrude(part, f, upd):
    pl = Plane(f["plane"])
    keys = EdgeKeys()
    fid = f["fid"]
    wires = [w for w, _c in _chain_wires(pl, f.get("chains", []), keys)]
    vec = gp_Vec(*[float(v) for v in f["vec"]])
    names = NameMap()
    shapes = []
    for w in wires:
        pr = BRepPrimAPI_MakePrism(w, vec)
        if not pr.IsDone():
            raise KernelError("Ekstrüde yüzey oluşturulamadı")
        for e in edges_of(w):
            k = keys.key_of(e)
            for g in pr.Generated(e):
                names.add(g, "F%s:s:%s" % (fid, k if k is not None else "?"))
        shapes.append(pr.Shape())
    return _add_surfaces(part, _surf_tool(shapes, names, fid))


def feat_srf_revolve(part, f, upd):
    pl = Plane(f["plane"])
    keys = EdgeKeys()
    fid = f["fid"]
    wires = [w for w, _c in _chain_wires(pl, f.get("chains", []), keys)]
    ax = gp_Ax1(gp_Pnt(*f["axis_o"]), gp_Dir(*f["axis_d"]))
    ang = math.radians(max(0.1, min(360.0, float(f.get("angle", 360.0)))))
    names = NameMap()
    shapes = []
    for w in wires:
        rv = BRepPrimAPI_MakeRevol(w, ax, ang, True)
        if not rv.IsDone():
            raise KernelError("Döndürülmüş yüzey oluşturulamadı")
        for e in edges_of(w):
            k = keys.key_of(e)
            for g in rv.Generated(e):
                names.add(g, "F%s:s:%s" % (fid, k if k is not None else "?"))
        shapes.append(rv.Shape())
    return _add_surfaces(part, _surf_tool(shapes, names, fid))


def feat_srf_loft(part, f, upd):
    from OCP.BRepOffsetAPI import BRepOffsetAPI_ThruSections
    ts = BRepOffsetAPI_ThruSections(False, bool(f.get("ruled", False)))
    n = 0
    for sec in f.get("sections", []):
        pl = Plane(sec["plane"])
        ws = _chain_wires(pl, [sec["curves"]], EdgeKeys())
        if ws:
            ts.AddWire(ws[0][0])
            n += 1
    if n < 2:
        raise KernelError("Loft yüzey için en az iki taslak gerekli")
    ts.Build()
    if not ts.IsDone():
        raise KernelError("Loft yüzey oluşturulamadı")
    return _add_surfaces(part, _surf_tool([ts.Shape()], NameMap(), f["fid"]))


def feat_srf_planar(part, f, upd):
    pl = Plane(f["plane"])
    faces = profile_faces(f, pl, EdgeKeys())
    return _add_surfaces(part, _surf_tool(faces, NameMap(), f["fid"]))


def _need_surfaces(part):
    surfs = surfaces_of(part.shape) if part is not None and not part.empty() else []
    if not surfs:
        raise KernelError("Modelde yüzey gövdesi yok")
    return surfs


def feat_srf_knit(part, f, upd):
    from OCP.BRepBuilderAPI import BRepBuilderAPI_Sewing
    from OCP.ShapeFix import ShapeFix_Solid
    surfs = _need_surfaces(part)
    sew = BRepBuilderAPI_Sewing(float(f.get("tol", 0.01)))
    for sh in surfs:
        sew.Add(sh)
    sew.Perform()
    sewn = sew.SewedShape()
    out = []
    made_solid = False
    if bool(f.get("solid", False)):
        shells = shape_list(sewn, TopAbs_SHELL)
        for shl in shells:
            if BRep_Tool.IsClosed_s(shl):
                ms = BRepBuilderAPI_MakeSolid(as_shell(shl))
                sf = ShapeFix_Solid(ms.Solid())
                sf.Perform()
                out.append(sf.Solid())
                made_solid = True
            else:
                out.append(shl)
        if not made_solid:
            raise KernelError("Dikilen yüzeyler kapalı değil: katı oluşturulamadı")
    else:
        out = [sewn]
    names = NameMap()
    rest = solids_of(part.shape)
    tool = Part(compound(rest + out), part.names.merged(names))
    name_new_faces(tool.shape, tool.names, "F%s" % f["fid"])
    return tool


def feat_srf_thicken(part, f, upd):
    from OCP.BRepOffsetAPI import BRepOffsetAPI_MakeThickSolid, BRepOffsetAPI_MakeOffsetShape
    surfs = _need_surfaces(part)
    t = float(f.get("t", 2.0))
    if t <= 0:
        raise KernelError("Kalınlık sıfırdan büyük olmalı")
    sign = -1.0 if bool(f.get("flip", False)) else 1.0
    solids = []
    for sh in surfs:
        src = sh
        if bool(f.get("mid", False)):
            mo = BRepOffsetAPI_MakeOffsetShape()
            mo.PerformBySimple(sh, -sign * t * 0.5)
            if not mo.IsDone():
                raise KernelError("Orta kalınlaştırma ofseti başarısız")
            src = mo.Shape()
        mk = BRepOffsetAPI_MakeThickSolid()
        mk.MakeThickSolidBySimple(src, sign * t)
        mk.Build()
        if not mk.IsDone():
            raise KernelError("Kalınlaştırma başarısız (yüzey çok kıvrımlı olabilir)")
        for so in (solids_of(mk.Shape()) or [mk.Shape()]):
            gp_ = GProp_GProps()
            BRepGProp.VolumeProperties_s(so, gp_)
            if gp_.Mass() < 0:
                so = so.Reversed()
            solids.append(so)
    tool = Part(compound(solids_of(part.shape) + solids), part.names)
    name_new_faces(tool.shape, tool.names, "F%s" % f["fid"])
    if bool(f.get("merge", True)) and solids_of(part.shape):
        return unify(Part(fuse_all(solids_of(tool.shape))[0], tool.names)) if len(solids_of(tool.shape)) > 1 else tool
    return tool


def feat_srf_trim(part, f, upd):
    surfs = _need_surfaces(part)
    o = [float(v) for v in f["o"]]
    n = [float(v) for v in f["n"]]
    size = max(100.0, diag_of(part.shape) * 4.0)
    out = []
    for sh in surfs:
        res = _halfspace_cut(sh, o, n, size)
        if not is_empty_shape(res):
            out.append(res)
    if not out:
        raise KernelError("Kırpma sonrası yüzey kalmadı (tarafı çevirin)")
    tool = Part(compound(solids_of(part.shape) + out), part.names)
    name_new_faces(tool.shape, tool.names, "F%s" % f["fid"])
    return tool


def feat_srf_offset(part, f, upd):
    from OCP.BRepOffsetAPI import BRepOffsetAPI_MakeOffsetShape
    surfs = _need_surfaces(part)
    d = float(f.get("d", 2.0))
    new = []
    for sh in surfs:
        mo = BRepOffsetAPI_MakeOffsetShape()
        mo.PerformBySimple(sh, d)
        if not mo.IsDone():
            raise KernelError("Ofset yüzey oluşturulamadı")
        new.append(mo.Shape())
    tool = Part(compound(new), NameMap())
    name_new_faces(tool.shape, tool.names, "F%s" % f["fid"])
    return _add_surfaces(part, tool)


# ---------------------------------------------------------------- Faz 8: doğrusal statik FEA (hex8 + uyumsuz modlar)

def _hex8_ke(h, E, nu):
    """Kenarları h = (hx, hy, hz) olan tuğla için uyumsuz modlu (Wilson) hex8 rijitlik matrisi (24x24), merkez B (6x24)."""
    import numpy as np
    lam = E * nu / ((1 + nu) * (1 - 2 * nu))
    mu = E / (2 * (1 + nu))
    D = np.zeros((6, 6))
    D[:3, :3] = lam
    D[0, 0] = D[1, 1] = D[2, 2] = lam + 2 * mu
    D[3, 3] = D[4, 4] = D[5, 5] = mu
    sg = [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]
    Jx, Jy, Jz = h[0] / 2.0, h[1] / 2.0, h[2] / 2.0
    def Bmat(xi, eta, ze):
        B = np.zeros((6, 33))
        for a, (sx, sy, sz) in enumerate(sg):
            dx = sx * (1 + sy * eta) * (1 + sz * ze) / 8.0 / Jx
            dy = sy * (1 + sx * xi) * (1 + sz * ze) / 8.0 / Jy
            dz = sz * (1 + sx * xi) * (1 + sy * eta) / 8.0 / Jz
            c = 3 * a
            B[0, c] = dx; B[1, c + 1] = dy; B[2, c + 2] = dz
            B[3, c] = dy; B[3, c + 1] = dx
            B[4, c + 1] = dz; B[4, c + 2] = dy
            B[5, c] = dz; B[5, c + 2] = dx
        # Uyumsuz modlar: (1-ξ²), (1-η²), (1-ζ²) her yer değiştirme bileşeni için
        dN = [(-2 * xi / Jx, 0, 0), (0, -2 * eta / Jy, 0), (0, 0, -2 * ze / Jz)]
        for m, (dx, dy, dz) in enumerate(dN):
            for comp in range(3):
                c = 24 + 3 * m + comp
                if comp == 0:
                    B[0, c] = dx; B[3, c] = dy; B[5, c] = dz
                elif comp == 1:
                    B[1, c] = dy; B[3, c] = dx; B[4, c] = dz
                else:
                    B[2, c] = dz; B[4, c] = dy; B[5, c] = dx
        return B
    g = 1.0 / math.sqrt(3.0)
    K = np.zeros((33, 33))
    for xi in (-g, g):
        for eta in (-g, g):
            for ze in (-g, g):
                B = Bmat(xi, eta, ze)
                K += B.T @ D @ B * (Jx * Jy * Jz)
    Kuu, Kua, Kaa = K[:24, :24], K[:24, 24:], K[24:, 24:]
    Ke = Kuu - Kua @ np.linalg.solve(Kaa, Kua.T)
    B0 = Bmat(0.0, 0.0, 0.0)[:, :24]
    return Ke, B0, D


def _voxelize(shape, h, box):
    """Sütun ışınlarıyla vokseller: dönüş (dolu maskesi nx*ny*nz, köşe, boyutlar)."""
    import numpy as np
    from OCP.IntCurvesFace import IntCurvesFace_ShapeIntersector
    from OCP.gp import gp_Lin
    x0, y0, z0, x1, y1, z1 = box
    nx = max(1, int(round((x1 - x0) / h)))
    ny = max(1, int(round((y1 - y0) / h)))
    nz = max(1, int(round((z1 - z0) / h)))
    hx, hy, hz = (x1 - x0) / nx, (y1 - y0) / ny, (z1 - z0) / nz
    ox, oy, oz = x0, y0, z0
    mask = np.zeros((nx, ny, nz), dtype=bool)
    inter = IntCurvesFace_ShapeIntersector()
    inter.Load(shape, 1e-7)
    zc = oz + (np.arange(nz) + 0.5) * hz
    for i in range(nx):
        for j in range(ny):
            px = ox + (i + 0.5) * hx
            py = oy + (j + 0.5) * hy
            inter.Perform(gp_Lin(gp_Pnt(px, py, oz - hz), gp_Dir(0, 0, 1)), -1e9, 1e9)
            ws = sorted(inter.WParameter(k) for k in range(1, inter.NbPnt() + 1))
            dd = []
            for w in ws:
                if not dd or abs(w - dd[-1]) > 1e-6:
                    dd.append(w)
            zs = [oz - hz + w for w in dd]
            if len(zs) % 2 == 1:
                zs = zs[:-1]
            for k in range(0, len(zs), 2):
                mask[i, j, (zc > zs[k]) & (zc < zs[k + 1])] = True
    return mask, (ox, oy, oz), (nx, ny, nz), (hx, hy, hz)


def _face_nodes(face, nodes_xyz, tol):
    """Yüz üzerinde (tol içinde) kalan düğüm indisleri."""
    import numpy as np
    from OCP.BRepClass import BRepClass_FaceClassifier
    from OCP.TopAbs import TopAbs_OUT
    s = BRepAdaptor_Surface(face)
    st = s.GetType()
    bb = Bnd_Box()
    BRepBndLib.Add_s(face, bb)
    lo, hi = bb.CornerMin(), bb.CornerMax()
    m = ((nodes_xyz[:, 0] > lo.X() - tol) & (nodes_xyz[:, 0] < hi.X() + tol) & (nodes_xyz[:, 1] > lo.Y() - tol) &
         (nodes_xyz[:, 1] < hi.Y() + tol) & (nodes_xyz[:, 2] > lo.Z() - tol) & (nodes_xyz[:, 2] < hi.Z() + tol))
    cand = np.nonzero(m)[0]
    out = []
    if st == GeomAbs_Plane:
        pl = s.Plane()
        p0 = pl.Location()
        d = pl.Axis().Direction()
        n = np.array([d.X(), d.Y(), d.Z()])
        dist = np.abs((nodes_xyz[cand] - np.array([p0.X(), p0.Y(), p0.Z()])) @ n)
        cand = cand[dist < tol]
        fc = BRepClass_FaceClassifier()
        for c in cand:
            q = nodes_xyz[c] - n * float((nodes_xyz[c] - np.array([p0.X(), p0.Y(), p0.Z()])) @ n)
            fc.Perform(face, gp_Pnt(*q.tolist()), tol)
            if fc.State() != TopAbs_OUT:
                out.append(int(c))
        return out
    for c in cand:
        if dist_to(nodes_xyz[c].tolist(), face) < tol:
            out.append(int(c))
    return out


def cmd_fea(req):
    try:
        import numpy as np
        import scipy.sparse as sp
        import scipy.sparse.linalg as spla
    except ImportError:
        return {"ok": False, "error": "Statik analiz için numpy ve scipy gerekli: OCC_Kur.bat dosyasını yeniden çalıştırın"}
    part = ST.part
    if part is None or part.empty() or not solids_of(part.shape):
        return {"ok": False, "error": "Modelde katı yok"}
    shape = solids_of(part.shape)[0] if len(solids_of(part.shape)) == 1 else compound(solids_of(part.shape))
    E = float(req.get("E", 210000.0))      # MPa (N/mm²)
    nu = float(req.get("nu", 0.3))
    target = int(req.get("elements", 6000))
    bb = Bnd_Box()
    BRepBndLib.Add_s(shape, bb)
    lo, hi = bb.CornerMin(), bb.CornerMax()
    box = (lo.X(), lo.Y(), lo.Z(), hi.X(), hi.Y(), hi.Z())
    props = GProp_GProps()
    BRepGProp.VolumeProperties_s(shape, props)
    vol = props.Mass()
    h = float(req.get("h", 0.0)) or (vol / max(50, target)) ** (1.0 / 3.0)
    t0 = time.perf_counter()
    mask, (ox, oy, oz), (nx, ny, nz), hh = _voxelize(shape, h, box)
    elems = np.argwhere(mask)
    ne = len(elems)
    if ne < 1:
        return {"ok": False, "error": "Ağ oluşturulamadı (eleman yok)"}
    # Düğüm numaralama (yalnızca kullanılan köşeler)
    corner = np.array([[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]])
    allc = (elems[:, None, :] + corner[None, :, :]).reshape(-1, 3)
    gid = allc[:, 0] * (ny + 1) * (nz + 1) + allc[:, 1] * (nz + 1) + allc[:, 2]
    uniq, inv = np.unique(gid, return_inverse=True)
    conn = inv.reshape(ne, 8)
    nn = len(uniq)
    gi = uniq // ((ny + 1) * (nz + 1))
    gj = (uniq // (nz + 1)) % (ny + 1)
    gk = uniq % (nz + 1)
    xyz = np.stack([ox + gi * hh[0], oy + gj * hh[1], oz + gk * hh[2]], axis=1)
    Ke, B0, D = _hex8_ke(hh, E, nu)
    dofs = (conn[:, :, None] * 3 + np.arange(3)[None, None, :]).reshape(ne, 24)
    rows = np.repeat(dofs, 24, axis=1).ravel()
    cols = np.tile(dofs, (1, 24)).ravel()
    vals = np.tile(Ke.ravel(), ne)
    K = sp.coo_matrix((vals, (rows, cols)), shape=(3 * nn, 3 * nn)).tocsr()
    F = np.zeros(3 * nn)
    fixed = np.zeros(3 * nn, dtype=bool)
    cnt = np.bincount(conn.ravel(), minlength=nn)
    tol = max(hh) * 0.75
    faces_all = faces_of(part.shape)
    nfix = 0
    for ref in req.get("fixtures", []):
        i, _fs = resolve_face(part, ref)
        if i < 0:
            return {"ok": False, "error": "Sabit yüz bulunamadı"}
        ids = _face_nodes(faces_all[i], xyz, tol)
        for c in ids:
            fixed[3 * c:3 * c + 3] = True
        nfix += len(ids)
    if nfix == 0:
        return {"ok": False, "error": "Sabitlenmiş düğüm yok: en az bir sabit yüz seçin"}
    for ld in req.get("loads", []):
        i, _fs = resolve_face(part, ld["face"])
        if i < 0:
            return {"ok": False, "error": "Yük yüzü bulunamadı"}
        ids = _face_nodes(faces_all[i], xyz, tol)
        if not ids:
            return {"ok": False, "error": "Yük yüzünde düğüm yok (ağı inceltin)"}
        # Tutarlı dağılım: düğüm ağırlığı = bağlı eleman sayısı (yüzeyde etki alanıyla orantılı)
        w = cnt[ids].astype(float)
        fv = np.array([float(v) for v in ld["force"]])
        for c, wc in zip(ids, w / w.sum()):
            F[3 * c:3 * c + 3] += fv * wc
    free = ~fixed
    u = np.zeros(3 * nn)
    Kff = K[free][:, free]
    try:
        u[free] = spla.spsolve(Kff.tocsc(), F[free], permc_spec="MMD_AT_PLUS_A")
    except Exception as exc:
        return {"ok": False, "error": "Çözücü hatası: %s" % exc}
    if not np.all(np.isfinite(u)):
        return {"ok": False, "error": "Çözüm kararsız: parça yeterince sabitlenmemiş"}
    ue = u[dofs]                       # ne x 24
    eps = ue @ B0.T                    # ne x 6
    sig = eps @ D.T
    sx, sy, sz, txy, tyz, tzx = sig.T
    vm = np.sqrt(0.5 * ((sx - sy) ** 2 + (sy - sz) ** 2 + (sz - sx) ** 2) + 3 * (txy ** 2 + tyz ** 2 + tzx ** 2))
    U = u.reshape(nn, 3)
    um = np.linalg.norm(U, axis=1)
    # Izgara düğüm yer değiştirmeleri (Godot tarafında örnekleme için)
    gdisp = np.zeros(((nx + 1) * (ny + 1) * (nz + 1), 3), dtype=np.float32)
    gdisp[uniq] = U
    evm = np.zeros(nx * ny * nz, dtype=np.float32) - 1.0
    eid = elems[:, 0] * ny * nz + elems[:, 1] * nz + elems[:, 2]
    evm[eid] = vm
    imax = int(np.argmax(vm))
    cmax = (np.array([ox, oy, oz]) + (elems[imax] + 0.5) * np.array(hh)).tolist()
    return {"ok": True, "elements": ne, "nodes": nn, "h": list(hh), "origin": [ox, oy, oz], "dims": [nx, ny, nz],
            "vm": b64f(evm.tolist()), "disp": b64f(gdisp.ravel().tolist()), "vm_max": float(vm.max()), "vm_min": float(vm.min()),
            "u_max": float(um.max()), "vm_max_at": cmax, "fixed_nodes": int(nfix), "solve_ms": round((time.perf_counter() - t0) * 1000.0, 1),
            "reaction": (lambda R: [float(R[0::3][fixed[0::3]].sum()), float(R[1::3][fixed[1::3]].sum()), float(R[2::3][fixed[2::3]].sum())])(K @ u - F)}


# ---------------------------------------------------------------- sunucu durumu

class State:
    def __init__(self):
        self.cache = {}          # zincir anahtarı -> (Part, error, upd)
        self.part = None
        self.store = {}          # montaj: parça anahtarı -> Part (Faz 7)
        self.store_cache = {}    # montaj: parça anahtarı -> özellik önbelleği


ST = State()

FEATURES = {"extrude": feat_extrude, "revolve": feat_revolve, "fillet": feat_fillet,
            "chamfer": feat_chamfer, "shell": feat_shell, "draft": feat_draft, "rib": feat_rib,
            "combine": feat_combine, "move_body": feat_move_body, "split": feat_split,
            "import": feat_import, "sweep": feat_sweep, "loft": feat_loft, "lpattern": feat_pattern,
            "cpattern": feat_pattern, "mirror": feat_pattern, "tpattern": feat_pattern, "hole": feat_hole,
            "dome": feat_dome, "cvpattern": feat_pattern, "projcurve": feat_projcurve, "wrap": feat_wrap,
            "emboss": feat_emboss, "prisms": feat_prisms, "weldment": feat_weldment,
            "srf_extrude": feat_srf_extrude, "srf_revolve": feat_srf_revolve, "srf_loft": feat_srf_loft, "srf_planar": feat_srf_planar,
            "srf_knit": feat_srf_knit, "srf_thicken": feat_srf_thicken, "srf_trim": feat_srf_trim, "srf_offset": feat_srf_offset}


def run_feature(part, f, upd):
    fn = FEATURES.get(f["type"])
    if fn is None:
        raise KernelError("Desteklenmeyen özellik: %s" % f["type"])
    return fn(part, f, upd)


def cmd_rebuild(req):
    feats = req.get("features", [])
    show_before = req.get("display_before", None)
    store = req.get("store")   # montaj parçası: ana parçanın durumuna dokunmadan ayrı saklanır
    old_cache = ST.store_cache.get(store, {}) if store else ST.cache
    part_before = None
    found_before = False
    key = hashlib.sha1(b"diycad-2").hexdigest()
    part = None
    errors = {}
    updates = {}
    new_cache = {}
    CUR_TOOLS.clear()
    CUR_CURVES.clear()
    for f in feats:
        if show_before is not None and f["fid"] == show_before:
            part_before = part
            found_before = True
        key = hashlib.sha1((key + json.dumps(f, sort_keys=True)).encode("utf-8")).hexdigest()
        hit = old_cache.get(key)
        if hit is not None:
            part, err, upd = hit
        else:
            upd = {}
            err = ""
            try:
                surfs_before = surfaces_of(part.shape) if part is not None and not part.empty() else []
                res = run_feature(part, f, upd)
                if res is None or res.shape is None or res.shape.IsNull():
                    raise KernelError("Sonuç boş")
                if surfs_before and not f["type"].startswith("srf_") and not surfaces_of(res.shape):
                    res = Part(compound(solids_of(res.shape) + surfs_before), res.names.merged(part.names))
                part = res
            except KernelError as exc:
                err = str(exc)
            except Exception as exc:  # OCC iç hataları
                err = "Çekirdek hatası: %s" % (str(exc) or type(exc).__name__)
        new_cache[key] = (part, err, upd)
        if upd.get("_tool") is not None and not err:
            CUR_TOOLS[int(f["fid"])] = upd["_tool"]
        if upd.get("_curve") is not None and not err:
            CUR_CURVES[int(f["fid"])] = upd["_curve"]
        if err:
            errors[str(f["fid"])] = err
        if upd:
            pu = upd.get("plane")
            rest = {k: v for k, v in upd.items() if k != "plane" and not k.startswith("_")}
            if rest:
                updates[str(f["fid"])] = rest
            if pu:
                updates.setdefault(str(pu["fid"]), {})["plane_o"] = pu["o"]
    if store:
        ST.store_cache[store] = new_cache
        ST.store[store] = part
    else:
        ST.cache = new_cache
        ST.part = part
    out = {"ok": True, "errors": errors, "updates": updates}
    if found_before:
        # Kenar/yüz seçimi için düzenlenen özellikten önceki gövde gösterilir
        part = part_before
        out["before"] = True
    if part is None or part.empty():
        out["empty"] = True
        return out
    diag = diag_of(part.shape)
    lin = float(req.get("lin", 0.0)) or max(0.002, diag * 0.0006)
    ang = float(req.get("ang", 0.0)) or 0.1
    mesh, faces, edges = mesh_shape(part, lin, ang)
    out["mesh"] = mesh
    out["faces"] = faces
    out["edges"] = edges
    out["mass"] = mass_of(part.shape)
    out["valid"] = BRepCheck_Analyzer(part.shape).IsValid()
    return out


def write_stl(shape, path, lin, ang, ascii_mode):
    """Şekli verilen sapma/açı ile üçgenleyip STL yazar (ikili veya ASCII)."""
    import struct
    BRepMesh_IncrementalMesh(shape, lin, False, ang, True)
    tris = []
    for face in faces_of(shape):
        loc = TopLoc_Location()
        tri = BRep_Tool.Triangulation_s(face, loc)
        if tri is None:
            continue
        trsf = loc.Transformation()
        nodes = [tri.Node(k).Transformed(trsf) for k in range(1, tri.NbNodes() + 1)]
        rev = face.Orientation() == TopAbs_REVERSED
        for k in range(1, tri.NbTriangles() + 1):
            a, b, c = tri.Triangle(k).Get()
            if rev:
                b, c = c, b
            pa, pb, pc = nodes[a - 1], nodes[b - 1], nodes[c - 1]
            ux, uy, uz = pb.X() - pa.X(), pb.Y() - pa.Y(), pb.Z() - pa.Z()
            vx, vy, vz = pc.X() - pa.X(), pc.Y() - pa.Y(), pc.Z() - pa.Z()
            nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
            tris.append(((nx / ln, ny / ln, nz / ln), (pa.X(), pa.Y(), pa.Z()), (pb.X(), pb.Y(), pb.Z()), (pc.X(), pc.Y(), pc.Z())))
    if ascii_mode:
        with open(path, "w", encoding="ascii") as fh:
            fh.write("solid diycad\n")
            for n, a, b, c in tris:
                fh.write("  facet normal %e %e %e\n    outer loop\n" % n)
                for v in (a, b, c):
                    fh.write("      vertex %e %e %e\n" % v)
                fh.write("    endloop\n  endfacet\n")
            fh.write("endsolid diycad\n")
    else:
        with open(path, "wb") as fh:
            fh.write(b"DIY.CAD STL (OpenCASCADE)".ljust(80, b" "))
            fh.write(struct.pack("<I", len(tris)))
            for n, a, b, c in tris:
                fh.write(struct.pack("<12fH", *n, *a, *b, *c, 0))
    return True


def cmd_export(req):
    part = ST.part
    if part is None or part.empty():
        return {"ok": False, "error": "Dışa aktarılacak model yok"}
    shape = part.shape
    fmt = req["format"]
    path = req["path"]
    if fmt == "step":
        w = STEPControl_Writer()
        w.Transfer(shape, STEPControl_AsIs)
        ok = w.Write(path) == IFSelect_RetDone
    elif fmt == "iges":
        w = IGESControl_Writer("MM", 0)
        w.AddShape(shape)
        w.ComputeModel()
        ok = bool(w.Write(path))
    elif fmt == "stl":
        lin = float(req.get("lin", 0.01))
        ang = math.radians(float(req.get("ang_deg", 10.0)))
        ok = write_stl(shape, path, lin, ang, bool(req.get("ascii", False)))
        # Ekran ağı ile aynı şekil üzerinde yeni üçgenleme yapıldı: bir sonraki rebuild yeniden ağlasın
        ST.cache = {}
    elif fmt == "brep":
        from OCP.BRepTools import BRepTools
        ok = bool(BRepTools.Write_s(shape, path))
    else:
        return {"ok": False, "error": "Bilinmeyen biçim: %s" % fmt}
    if not ok:
        return {"ok": False, "error": "Dosya yazılamadı"}
    return {"ok": True, "path": path, "bytes": os.path.getsize(path) if os.path.exists(path) else 0}


# ---------------------------------------------------------------- montaj (Faz 7)

def _asm_trsf(m):
    """m: 3x4 satır düzenli dönüşüm [r00 r01 r02 tx r10 ... tz] → gp_Trsf"""
    t = gp_Trsf()
    t.SetValues(*[float(v) for v in m])
    return t


def _asm_shapes(req):
    out = []
    for c in req.get("comps", []):
        part = ST.store.get(c["key"])
        if part is None or part.empty():
            out.append(None)
            continue
        out.append(BRepBuilderAPI_Transform(part.shape, _asm_trsf(c["m"]), True).Shape())
    return out


def _tri_list(shape, defl):
    """Şekli üçgenleyip düz köşe listesi (x,y,z ×3 / üçgen) döndürür."""
    BRepMesh_IncrementalMesh(shape, defl, False, 0.3, True)
    flat = []
    for face in faces_of(shape):
        loc = TopLoc_Location()
        tri = BRep_Tool.Triangulation_s(face, loc)
        if tri is None:
            continue
        trsf = loc.Transformation()
        nodes = [tri.Node(k).Transformed(trsf) for k in range(1, tri.NbNodes() + 1)]
        rev = face.Orientation() == TopAbs_REVERSED
        for k in range(1, tri.NbTriangles() + 1):
            a, b, c = tri.Triangle(k).Get()
            if rev:
                b, c = c, b
            for q in (nodes[a - 1], nodes[b - 1], nodes[c - 1]):
                flat.extend((q.X(), q.Y(), q.Z()))
    return flat


def cmd_asm_interference(req):
    """Bileşen çiftlerinin ortak hacmi (girişim). Dönüş: pairs [{a, b, volume, center, tris(b64)}]"""
    shapes = _asm_shapes(req)
    boxes = []
    for sh in shapes:
        if sh is None:
            boxes.append(None)
            continue
        bb = Bnd_Box()
        BRepBndLib.Add_s(sh, bb)
        boxes.append(bb)
    min_vol = float(req.get("min_volume", 1e-6))
    pairs = []
    for i in range(len(shapes)):
        for j in range(i + 1, len(shapes)):
            if shapes[i] is None or shapes[j] is None or boxes[i].IsOut(boxes[j]):
                continue
            try:
                com = BRepAlgoAPI_Common(shapes[i], shapes[j]).Shape()
            except Exception:
                continue
            if com is None or com.IsNull() or is_empty_shape(com):
                continue
            props = GProp_GProps()
            BRepGProp.VolumeProperties_s(com, props)
            vol = props.Mass()
            if vol <= min_vol:
                continue
            c = props.CentreOfMass()
            defl = max(0.01, diag_of(com) * 0.002)
            pairs.append({"a": i, "b": j, "volume": vol, "center": [c.X(), c.Y(), c.Z()],
                          "tris": b64f(_tri_list(com, defl))})
    return {"ok": True, "pairs": pairs}


def cmd_asm_collide(req):
    """Sürüklenen bileşenler (moving) ile diğerleri (others) arasında hacimsel çakışma var mı?
    Değen yüzler (sıfır hacim) çarpışma sayılmaz. İlk çakışmada durur."""
    mv = _asm_shapes({"comps": req.get("moving", [])})
    ot = _asm_shapes({"comps": req.get("others", [])})
    min_vol = float(req.get("min_volume", 1e-3))
    boxes = []
    for sh in ot:
        if sh is None:
            boxes.append(None)
            continue
        bb = Bnd_Box()
        BRepBndLib.Add_s(sh, bb)
        boxes.append(bb)
    for i, a in enumerate(mv):
        if a is None:
            continue
        ba = Bnd_Box()
        BRepBndLib.Add_s(a, ba)
        for j, b in enumerate(ot):
            if b is None or ba.IsOut(boxes[j]):
                continue
            try:
                com = BRepAlgoAPI_Common(a, b).Shape()
            except Exception:
                continue
            if com is None or com.IsNull() or is_empty_shape(com):
                continue
            props = GProp_GProps()
            BRepGProp.VolumeProperties_s(com, props)
            if props.Mass() > min_vol:
                return {"ok": True, "hit": True, "pairs": [[i, j, props.Mass()]], "n_moving": len(mv)}
    return {"ok": True, "hit": False, "pairs": [], "n_moving": len(mv)}


def cmd_asm_export(req):
    shapes = [sh for sh in _asm_shapes(req) if sh is not None]
    if not shapes:
        return {"ok": False, "error": "Dışa aktarılacak bileşen yok"}
    comp = TopoDS_Compound()
    bld = BRep_Builder()
    bld.MakeCompound(comp)
    for sh in shapes:
        bld.Add(comp, sh)
    path = req["path"]
    fmt = req.get("format", "step")
    if fmt == "step":
        w = STEPControl_Writer()
        w.Transfer(comp, STEPControl_AsIs)
        ok = w.Write(path) == IFSelect_RetDone
    elif fmt == "stl":
        ok = write_stl(comp, path, float(req.get("lin", 0.01)), math.radians(float(req.get("ang_deg", 10.0))), bool(req.get("ascii", False)))
    else:
        return {"ok": False, "error": "Bilinmeyen biçim: %s" % fmt}
    if not ok:
        return {"ok": False, "error": "Dosya yazılamadı"}
    return {"ok": True, "path": path, "bytes": os.path.getsize(path) if os.path.exists(path) else 0}


def main():
    send({"id": 0, "ready": True, "version": OCP_VERSION})
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        rid = 0
        try:
            req = json.loads(line)
            rid = req.get("id", 0)
            if "file" in req:
                # Büyük istekler geçici dosyayla gelir
                fpath = req["file"]
                with open(fpath, "r", encoding="utf-8") as fh:
                    req = json.load(fh)
                try:
                    os.remove(fpath)
                except OSError:
                    pass
                rid = req.get("id", rid)
            cmd = req.get("cmd", "")
            t0 = time.perf_counter()
            if cmd == "ping":
                res = {"ok": True, "version": OCP_VERSION}
            elif cmd == "rebuild":
                res = cmd_rebuild(req)
            elif cmd == "export":
                res = cmd_export(req)
            elif cmd == "hlr":
                res = cmd_hlr(req)
            elif cmd == "asm_interference":
                res = cmd_asm_interference(req)
            elif cmd == "asm_export":
                res = cmd_asm_export(req)
            elif cmd == "asm_collide":
                res = cmd_asm_collide(req)
            elif cmd == "fea":
                res = cmd_fea(req)
            elif cmd == "quit":
                send({"id": rid, "ok": True})
                break
            else:
                res = {"ok": False, "error": "Bilinmeyen komut: %s" % cmd}
            res["id"] = rid
            res["ms"] = round((time.perf_counter() - t0) * 1000.0, 1)
            send(res)
        except Exception as exc:
            send({"id": rid, "ok": False, "error": "%s: %s" % (type(exc).__name__, exc),
                  "trace": traceback.format_exc()[-2000:]})


if __name__ == "__main__":
    main()
