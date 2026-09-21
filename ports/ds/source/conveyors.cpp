#include "simulation.hpp"
#include "geometry.hpp"
#include <algorithm>
#include <cassert>

namespace dx {
point simulation::beltlocal(int index, point position) const {
    const auto d = position-definition.belts[index].position;
    const auto& b = belts[index];
    return {b.c*d.x-b.s*d.y,b.pc*d.x+b.ps*d.y};
}
point simulation::beltworld(int index, float x, float y) const {
    const auto p = definition.belts[index].position; const auto& b = belts[index];
    return {p.x+b.c*x-b.s*y,p.y-b.s*x-b.c*y};
}
bool simulation::belthit(int index, point position, float radius) const {
    const auto p = beltlocal(index,position); const auto& b = definition.belts[index];
    return p.x >= -radius && p.x <= b.length+radius && p.y >= -b.width*.5f-radius && p.y <= b.width*.5f+radius;
}
float simulation::beltscale(int kind, int index) const {
    for (int i=0;i<beltitemsused;++i) if (beltitems[i].kind==kind && beltitems[i].index==index) return beltitems[i].scale;
    return 1;
}
bool simulation::belted(int kind, int index) const {
    for (int i=0;i<beltitemsused;++i) if (beltitems[i].kind==kind && beltitems[i].index==index) return beltitems[i].belt>=0;
    return false;
}
point simulation::beltpoint(const beltitem& item) const {
    const int i=item.index;
    switch (item.kind) {
    case 0: return definition.bubbles[i];
    case 1: return starpositions[i];
    case 2: return definition.bouncers[i].position;
    case 3: return definition.hats[i].position+rotate(point{-9,75}*(item.scale==1?.7f:item.scale),definition.hats[i].angle);
    case 4: return definition.tubes[i].position+rotate({0,168*.45f*item.scale},definition.tubes[i].angle);
    case 5: return definition.pumps[i].position+rotate({761*.01f*item.scale,0},definition.pumps[i].angle);
    default: return anchors[i];
    }
}
void simulation::setbeltpoint(beltitem& item, point position) {
    const int i=item.index;
    switch (item.kind) {
    case 0: definition.bubbles[i]=position; break;
    case 1: starpositions[i]=position; break;
    case 2: definition.bouncers[i].position=position; break;
    case 3: definition.hats[i].position=position-rotate(point{-9,75}*(item.scale==1?.7f:item.scale),definition.hats[i].angle); break;
    case 4: definition.tubes[i].position=position-rotate({0,168*.45f*item.scale},definition.tubes[i].angle); break;
    case 5: definition.pumps[i].position=position-rotate({761*.01f*item.scale,0},definition.pumps[i].angle); break;
    default: anchors[i]=position; break;
    }
}
void simulation::sortbelts() {
    for (int pass=0;pass<2;++pass) {
        int last=definition.beltcount-1;
        for (int i=last;i>=0;--i) {
            const int id=beltorder[i];
            if (pass ? !definition.belts[id].manual : definition.belts[id].manual && belts[id].active) {
                for (int j=i;j<last;++j) std::swap(beltorder[j],beltorder[j+1]);
                --last;
            }
        }
    }
}
void simulation::bindbelt(int index, int id) {
    auto& item=beltitems[id]; auto& b=belts[index]; const float length=definition.belts[index].length;
    assert(b.count < static_cast<int>(b.items.size()));
    b.items[b.count++]=id; item.belt=index; item.position=beltlocal(index,beltpoint(item)).x;
    if (item.position<0 || item.position>length) {
        item.position=item.position>=length*.5f?length-18:18;
        setbeltpoint(item,beltworld(index,item.position,0));
    }
    b.distributed=false;
}
void simulation::removebeltitem(int kind, int index) {
    for (int n=0;n<beltitemsused;++n) {
        auto& item=beltitems[n];
        if (item.kind!=kind || item.index!=index || item.belt<0) continue;
        auto& b=belts[item.belt];
        for (int i=0;i<b.count;++i) if (b.items[i]==n) {
            for (int j=i+1;j<b.count;++j) b.items[j-1]=b.items[j];
            --b.count; break;
        }
        item.belt=-1;
    }
}
void simulation::resetbelts() {
    belts={}; beltitems={}; beltitemsused=beltrevision=beltwraps=belthandoffs=beltevents=beltsound=0; heldbelt=-1;
    for (int i=0;i<definition.beltcount;++i) {
        auto& b=belts[i]; const float angle=definition.belts[i].angle*3.14159265f/180;
        b.c=std::cos(angle); b.s=std::sin(angle);
        const float perpendicular=-angle-3.14159265f/2;
        b.pc=std::cos(perpendicular); b.ps=std::sin(perpendicular); beltorder[i]=i;
    }
    if (!definition.beltcount) return;
    sortbelts();
    const int counts[]={definition.bubblecount,3,definition.bouncercount,definition.hatcount,definition.tubecount,definition.pumpcount,definition.hookcount};
    const float radii[]={85,60,40,90,52.5f,761*.13f,40};
    for (int kind=0;kind<7;++kind) for (int index=0;index<counts[kind];++index) {
        if (kind==6 && (definition.hooks[index].route>=0 || definition.hooks[index].rail || ghostapp(4,index))) continue;
        assert(beltitemsused < static_cast<int>(beltitems.size()));
        const int id=beltitemsused++; auto& item=beltitems[id];
        item.kind=kind; item.index=index; item.radius=radii[kind];
        if (kind==3) { item.minimum=.35f; item.maximum=.7f; }
        if (kind==4) item.minimum=.7f;
        for (int n=0;n<definition.beltcount;++n) if (belthit(beltorder[n],beltpoint(item),item.radius*.6f)) { bindbelt(beltorder[n],id); break; }
    }
}
void simulation::movebelt(int index, float delta) {
    auto& b=belts[index]; const float length=definition.belts[index].length;
    b.offset+=delta; while (b.offset>length) b.offset-=63; while (b.offset<0) b.offset+=63;
    for (int n=0;n<b.count;++n) {
        auto& item=beltitems[b.items[n]]; const float perpendicular=beltlocal(index,beltpoint(item)).y;
        float position=item.position-delta; const float span=length-36;
        int crossings=0;
        if (span>0 && position<18) crossings=static_cast<int>(std::ceil((18-position)/span));
        else if (span>0 && position>length-18) crossings=-static_cast<int>(std::ceil((position-(length-18))/span));
        position+=crossings*span; item.position=position;
        const bool right=position>=length*.5f; const float distance=right?length-position:position;
        item.scale=item.maximum;
        if (distance<item.radius*item.maximum) {
            item.scale=item.minimum+distance*(item.maximum-item.minimum)/(item.radius*item.maximum);
            position=right?length-item.scale*item.radius:item.scale*item.radius;
        }
        setbeltpoint(item,beltworld(index,position,perpendicular));
        if (crossings) {
            b.distributed=false; ++beltwraps; ++beltevents; beltsound=0;
            if (item.kind==6) {
                auto& rope=ropes[item.index];
                if (!rope.count) continue;
                if (definition.hooks[item.index].radius<0) for (int i=0;i<definition.hookcount;++i)
                    if (i!=item.index && ropes[i].count && !ropes[i].cut && ropes[i].candy==rope.candy) sever(i,ropes[i].count-2);
                if (!rope.cut) {
                    const auto shift=anchors[item.index]-bodies[rope.bodies[0]].pos;
                    for (int i=0;i<rope.count;++i) {
                        auto& body=bodies[rope.bodies[i]];
                        body.pos=body.pos+shift; body.previous=body.previous+shift; body.pin=body.pin+shift;
                    }
                }
            }
        }
    }
    for (int n=0;n<definition.beltcount;++n) {
        const int owner=beltorder[n];
        if (owner==index || !definition.belts[owner].manual) continue;
        auto& other=belts[owner];
        for (int i=other.count-1;i>=0;--i) {
            const int id=other.items[i]; auto& item=beltitems[id];
            if (belthit(index,beltpoint(item),item.radius*.6f) && (!definition.belts[index].manual || b.activation>=other.activation)) {
                removebeltitem(item.kind,item.index); bindbelt(index,id); ++belthandoffs; ++beltevents; beltsound=1;
            }
        }
    }
}
void simulation::alignbelt(int index) {
    auto& b=belts[index]; const float length=definition.belts[index].length;
    b.alignment=0; float nearest=1e30f;
    for (int i=0;i<b.count;++i) {
        const auto& item=beltitems[b.items[i]]; const bool right=item.position>=length*.5f;
        const float distance=right?length-item.position:item.position;
        if (distance<item.radius && distance<nearest) { nearest=distance; b.alignment=right?1:-1; }
    }
}
void simulation::updatebelts() {
    for (int n=0;n<definition.beltcount;++n) {
        const int id=beltorder[n]; auto& b=belts[id]; const auto& source=definition.belts[id];
        if (!source.manual) { b.delta=.016f*source.velocity; movebelt(id,b.delta); }
        b.active=std::abs(b.delta)>3;
        if (source.manual && b.active) {
            b.travel+=std::abs(b.delta);
            if (b.travel>=45) { b.travel=0; ++beltevents; beltsound=2+beltevents%4; }
        }
        if (source.manual && heldbelt!=id) {
            if (std::abs(b.delta)<=3) { b.delta=0; if (!b.alignment) alignbelt(id); }
            else { b.delta*=.75f; if (b.active) movebelt(id,b.delta); }
        }
        for (int i=0;i<b.count;++i) {
            auto& item=beltitems[b.items[i]]; const auto p=beltlocal(id,beltpoint(item));
            if (std::abs(p.y)>.01f) setbeltpoint(item,beltworld(id,p.x,std::abs(p.y)<=2?0:p.y*.8f));
        }
        if (!b.distributed && b.count>=2) {
            b.distributed=true;
            auto push=[&](beltitem& item,float pos,float distance) {
                float next=pos+distance;
                if (next<=18 || next>=source.length-18) next=pos<source.length*.5f?18:source.length-18;
                item.position=next;
            };
            for (int i=0;i<b.count;++i) for (int j=i+1;j<b.count;++j) {
                auto& a=beltitems[b.items[i]]; auto& v=beltitems[b.items[j]];
                const float required=a.radius+v.radius+6, pa=a.position, pb=v.position;
                const float difference=pa-pb, distance=std::abs(difference);
                if (std::abs(required-distance)>=1 && distance<required) {
                    const float norm=distance<=.0001f?1:difference/distance;
                    const float amount=(required-distance)*norm*.016f;
                    push(a,pa,amount*10); push(v,pb,amount*-10); b.distributed=false;
                }
            }
            if (!b.distributed) movebelt(id,0);
        }
        if (b.alignment) { movebelt(id,b.alignment*240*.016f); b.alignment=0; }
    }
    sortbelts();
}
bool simulation::pressbelt(point position) {
    if (heldbelt>=0) return false;
    auto candidates=beltorder;
    for (int i=1;i<definition.beltcount;++i) for (int j=i;j>0 && belts[candidates[j]].activation>belts[candidates[j-1]].activation;--j)
        std::swap(candidates[j],candidates[j-1]);
    for (int n=0;n<definition.beltcount;++n) {
        const int id=candidates[n]; if (!definition.belts[id].manual) continue;
        auto& b=belts[id]; b.alignment=0;
        if (belthit(id,position,0)) { b.activation=++beltrevision; b.last=beltlocal(id,position); b.delta=0; heldbelt=id; return true; }
    }
    return false;
}
bool simulation::dragbelt(point position) {
    if (heldbelt<0) return false;
    auto& b=belts[heldbelt]; const auto p=beltlocal(heldbelt,position);
    b.delta=b.last.x-p.x; movebelt(heldbelt,b.delta); b.last=p; return true;
}
void simulation::releasebelt(point position) {
    if (heldbelt<0) return;
    const int id=heldbelt; auto& b=belts[id]; heldbelt=-1;
    b.delta=b.last.x-beltlocal(id,position).x;
    if (std::abs(b.delta)<=3) { b.delta=0; if (!b.alignment) alignbelt(id); }
}
void simulation::cancelbelts() {
    heldbelt=-1;
    for (int i=0;i<definition.beltcount;++i) if (definition.belts[i].manual) {
        auto& b=belts[i]; b.delta=b.travel=0; b.active=false; b.alignment=0;
    }
}
}
