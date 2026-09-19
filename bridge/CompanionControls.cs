using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

// Only this small surface repaints on animation ticks; the roster stays stable.
// Segment count indicates loading stages, never a fabricated byte percentage.
public sealed class CompanionLoadBar : Control {
 public int Stage;public double Sweep;
 public CompanionLoadBar(){SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);}
 protected override void OnPaint(PaintEventArgs e){
  float gap=Width*.012f,w=(Width-gap*4)/5f,y=Height*.35f,h=Math.Max(3,Height*.22f);
  for(int i=0;i<5;i++)using(var b=new SolidBrush(i<Stage?Color.FromArgb(180,151,96):Color.FromArgb(55,51,39)))e.Graphics.FillRectangle(b,i*(w+gap),y,w,h);
  if(Stage<5){float x=(float)(Sweep%1)*(Width+Width*.16f)-Width*.16f;
   using(var b=new SolidBrush(Color.FromArgb(239,219,172)))e.Graphics.FillRectangle(b,x,y,Width*.10f,h);
  }
 }
}

public sealed class CompanionButton : Button {
    bool hovered; string caption=""; bool selected;
    public string Caption {get{return caption;}set{if(caption==value)return;caption=value;Invalidate();}}
    public bool Selected {get{return selected;}set{if(selected==value)return;selected=value;Invalidate();}}
    public bool TabStyle,Cycle;
    public CompanionButton(){SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);}
    protected override void OnMouseEnter(EventArgs e){hovered=true;Invalidate();base.OnMouseEnter(e);}
    protected override void OnMouseLeave(EventArgs e){hovered=false;Invalidate();base.OnMouseLeave(e);}
    protected override void OnPaint(PaintEventArgs e){
        var g=e.Graphics;g.TextRenderingHint=System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
        Color border=Selected?Color.FromArgb(197,164,102):Color.FromArgb(82,76,60);
        using(var b=new SolidBrush(Enabled&&(hovered||Selected)?Color.FromArgb(51,45,34):BackColor))g.FillRectangle(b,ClientRectangle);
        using(var p=new Pen(border)){if(TabStyle)g.DrawLine(p,0,Height-1,Width,Height-1);else g.DrawRectangle(p,0,0,Width-1,Height-1);}
        using(var b=new SolidBrush(Enabled?ForeColor:Color.FromArgb(130,126,116)))using(var format=new StringFormat{Alignment=caption==""?StringAlignment.Center:StringAlignment.Near,LineAlignment=StringAlignment.Center,Trimming=StringTrimming.EllipsisCharacter,FormatFlags=StringFormatFlags.NoWrap}){
            float inset=Font.Size*.8f;
            if(caption=="")g.DrawString(Text,Font,b,new RectangleF(inset,0,Width-2*inset-(Cycle?inset:0),Height),format);
            else{
                using(var small=new Font(Font.FontFamily,Font.Size*.69f,FontStyle.Regular,GraphicsUnit.Pixel))using(var muted=new SolidBrush(Color.FromArgb(169,153,123)))
                    g.DrawString(caption,small,muted,new RectangleF(inset,Height*.1f,Width-2*inset,Height*.3f),format);
                g.DrawString(Text,Font,b,new RectangleF(inset,Height*.38f,Width-2*inset,Height*.5f),format);
            }
        }
        if(Cycle)using(var b=new SolidBrush(Color.FromArgb(166,144,102)))g.DrawString("›",Font,b,new PointF(Width-Font.Size*1.1f,Height*.5f-Font.Height*.5f));
    }
}

// The native ListBox painted its entire surface on every state poll. This
// buffered control repaints only changed selection/hover rows or party badges.
// It never captures the mouse, restores focus, or rebuilds its item handles.
public sealed class CompanionRoster : Control {
    public readonly List<CompanionCandidate> Items=new List<CompanionCandidate>();
    readonly HashSet<string> members=new HashSet<string>();
    int selected=-1,hovered=-1,first,rowHeight=28;
    public event EventHandler SelectedIndexChanged;
    public int ItemHeight {get{return rowHeight;}set{if(rowHeight==value)return;rowHeight=value;Invalidate();}}
    public int SelectedIndex {get{return selected;}set{
        if(value==selected||value<0||value>=Items.Count)return;
        int old=selected;selected=value;InvalidateRow(old);InvalidateRow(selected);
        if(SelectedIndexChanged!=null)SelectedIndexChanged(this,EventArgs.Empty);
    }}
    public CompanionCandidate SelectedItem {get{return selected<0||selected>=Items.Count?null:Items[selected];}}
    public CompanionRoster(){SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.ResizeRedraw,true);TabStop=false;}
    void InvalidateRow(int index){if(index>=first)Invalidate(new Rectangle(0,(index-first)*rowHeight,Width,rowHeight));}
    public void ReplaceItems(CompanionCandidate[] next,string keep){
        Items.Clear();Items.AddRange(next);selected=-1;hovered=-1;first=Math.Min(first,Math.Max(0,Items.Count-Height/rowHeight));
        int index=Items.FindIndex(c=>c.id==keep);if(Items.Count>0)SelectedIndex=Math.Max(0,index);Invalidate();
    }
    public void SetMembers(CompanionMember[] next){
        var ids=new HashSet<string>();if(next!=null)foreach(var m in next){ids.Add(m.id);ids.Add(m.characterId??m.id);}
        if(members.SetEquals(ids))return;
        for(int i=0;i<Items.Count;i++)if(members.Contains(Items[i].id)!=ids.Contains(Items[i].id))InvalidateRow(i);
        members.Clear();members.UnionWith(ids);
    }
    protected override void OnMouseMove(MouseEventArgs e){int n=first+e.Y/rowHeight;if(n>=Items.Count)n=-1;if(n!=hovered){int old=hovered;hovered=n;InvalidateRow(old);InvalidateRow(n);}base.OnMouseMove(e);}
    protected override void OnMouseLeave(EventArgs e){int old=hovered;hovered=-1;InvalidateRow(old);base.OnMouseLeave(e);}
    protected override void OnMouseDown(MouseEventArgs e){if(e.Button==MouseButtons.Left)SelectedIndex=first+e.Y/rowHeight;base.OnMouseDown(e);}
    protected override void OnMouseWheel(MouseEventArgs e){int next=Math.Max(0,Math.Min(Math.Max(0,Items.Count-Height/rowHeight),first-Math.Sign(e.Delta)*3));if(first!=next){first=next;Invalidate();}base.OnMouseWheel(e);}
    protected override void OnPaint(PaintEventArgs e){
        var g=e.Graphics;g.TextRenderingHint=System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
        using(var bg=new SolidBrush(BackColor))g.FillRectangle(bg,e.ClipRectangle);
        for(int i=first;i<Items.Count;i++){
            int y=(i-first)*rowHeight;if(y>=Height)break;var r=new Rectangle(0,y,Width,rowHeight);
            if(!r.IntersectsWith(e.ClipRectangle))continue;
            bool chosen=i==selected;bool member=members.Contains(Items[i].id);
            if(chosen||i==hovered)using(var b=new SolidBrush(chosen?Color.FromArgb(55,47,33):Color.FromArgb(34,32,27)))g.FillRectangle(b,r);
            using(var pen=new Pen(chosen?Color.FromArgb(190,159,103):Color.FromArgb(46,43,35)))g.DrawLine(pen,chosen?0:12,y+rowHeight-1,Width-12,y+rowHeight-1);
            if(chosen)using(var b=new SolidBrush(Color.FromArgb(199,169,111)))g.FillRectangle(b,0,y,3,rowHeight);
            using(var b=new SolidBrush(chosen?Color.FromArgb(247,236,211):Color.FromArgb(203,194,176)))using(var f=new StringFormat{LineAlignment=StringAlignment.Center,Trimming=StringTrimming.EllipsisCharacter,FormatFlags=StringFormatFlags.NoWrap})
                g.DrawString(Items[i].name.Length>24?Items[i].name.Split(new[]{" / "},StringSplitOptions.None)[0]:Items[i].name,Font,b,new RectangleF(14,y,Width-42,rowHeight),f);
            if(member){float x=Width-19,cy=y+rowHeight*.5f,d=rowHeight*.13f;using(var b=new SolidBrush(Color.FromArgb(193,162,103)))g.FillPolygon(b,new[]{new PointF(x,cy-d),new PointF(x+d,cy),new PointF(x,cy+d),new PointF(x-d,cy)});}
        }
    }
}
