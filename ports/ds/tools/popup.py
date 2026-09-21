import json
import uiscale
import menulayout


def build(menu):
    fit=menu["fit"]*uiscale.popup
    menu["quad"]("popuppaper","menu_popup",0,factor=fit*1.2,restore=True,group="popup")
    for i,name in enumerate(("popupup","popupdown")):
        menu["quad"](name,"menu_buttons",i,factor=fit,group="menu_buttonspopup")
    frames=json.loads((menu["content"]/"images/menu_popup.json").read_text())["frames"]
    paper=next(item for item in menu["records"] if item["name"]=="popuppaper")
    origin,positions=menulayout.popup(dict(oy=paper["oy"],h=paper["image"].height),fit,frames)
    labels=[]
    for code in menu["codes"]:
        strings={**menu["locale"]("en"),**menu["locale"](code)}
        row=[]
        for index,(key,small,wrap) in enumerate((("GAME_FINISHED_TEXT",False,600),("GAME_FINISHED_THANKS",True,700),("OK",False,None))):
            name="popup"+code+str(index)
            menu["label"](name,strings[key],code,small,wrap,factor=fit,group="textpopup"+code)
            row.append(name)
        labels.append(row)
    return dict(origin=origin,positions=positions,labels=labels)


def header(info,ids):
    return ["inline constexpr int popuporigin[2] = {"+",".join(map(str,info["origin"]))+"};",
            "inline constexpr int popuppositions[3][2] = {"+",".join("{"+",".join(map(str,p))+"}" for p in info["positions"])+"};",
            "inline constexpr int popuplabels[12][3] = {"+",".join("{"+",".join(str(ids[name]) for name in row)+"}" for row in info["labels"])+"};"]
