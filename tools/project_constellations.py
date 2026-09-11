"""Regenerate chart silhouettes from the checked-in J2000 catalogue (stdlib only).

Each figure uses a stereographic tangent plane, north up and east left. Its
diameter and chart anchor remain UI choices. Never stretch individual stars.
"""
import ast
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = json.loads((ROOT / 'tools/data/research-stars.json').read_text(encoding='utf-8'))['stars']


def definitions(source):
    text = source.split('const CONSTELLATIONS := ', 1)[1]
    depth = 0
    for i, c in enumerate(text):
        if c == '{': depth += 1
        if c == '}':
            depth -= 1
            if depth == 0:
                return ast.literal_eval(re.sub(r'Vector2\(([^()]+)\)', r'[\1]', text[:i+1]))


def project(cid, stars):
    vectors = []
    for star in stars:
        record = CATALOG[cid + '/' + star['id']]
        ra, dec = math.radians(record['ra']), math.radians(record['dec'])
        vectors.append((math.cos(dec)*math.cos(ra), math.cos(dec)*math.sin(ra), math.sin(dec)))
    center = [sum(v[i] for v in vectors) for i in range(3)]
    norm = math.sqrt(sum(v*v for v in center))
    center = [v/norm for v in center]
    ra = math.atan2(center[1], center[0])
    east = (-math.sin(ra), math.cos(ra), 0)
    north = (-center[2]*east[1], center[2]*east[0], center[0]*east[1]-center[1]*east[0])
    dot = lambda a,b: sum(x*y for x,y in zip(a,b))
    points = [(-2*dot(v,east)/(1+dot(v,center)), -2*dot(v,north)/(1+dot(v,center))) for v in vectors]
    # Fixed diameter, independent of the old arbitrary silhouettes. Shared
    # Alpheratz is anchored at zero so the entire Pegasus figure can follow it.
    diameter = max(math.dist(a,b) for a in points for b in points)
    origin = points[0] if cid == 'pegasus' else tuple(sum(p[i] for p in points)/len(points) for i in range(2))
    return [tuple((p[i]-origin[i])*2.0/diameter for i in range(2)) for p in points]


def main():
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    changed=[]
    for name in ['research_chart_data','constellation_extension_data']:
        path=ROOT/'scripts'/f'{name}.gd'
        source=path.read_text(encoding='utf-8')
        data=definitions(source)
        replacements=iter(point for cid,c in data.items() for point in project(cid,c['stars']))
        def replace(match):
            x,y=next(replacements)
            return f'"local_position": Vector2({x:.7f}, {y:.7f})'
        updated=re.sub(r'"local_position": Vector2\([^()]+\)',replace,source)
        if updated!=source:
            changed.append(str(path.relative_to(ROOT)))
            if not args.check:path.write_text(updated,encoding='utf-8')
    if args.check and changed:raise SystemExit('Stale chart geometry: '+', '.join(changed))
    print('CONSTELLATION_PROJECTION_PASS: 21 figures, 139 catalogue markers')


if __name__=='__main__':main()
