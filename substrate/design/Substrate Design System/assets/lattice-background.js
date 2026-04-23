// Triangular lattice (deltille / A2) background pattern.
// Dots at vertices, edges between nearest neighbours. Spacing = 40px.
// Color tokens pulled from --dot-color / --line-color with sensible defaults.
(function(){
  function install(target, opts){
    opts = opts || {};
    var spacing = opts.spacing || 26;
    var dotRadius = opts.dotRadius || 1.4;
    // Pine-700 (#2F4738) at low alpha — ties dots/lines to the logo's
    // surface green rather than a neutral gray.
    var dotColor = opts.dotColor || 'rgba(47, 71, 56, 0.26)';
    var lineColor = opts.lineColor || 'rgba(47, 71, 56, 0.11)';
    var lineWidth = opts.lineWidth || 0.55;

    var canvas = document.createElement('canvas');
    canvas.setAttribute('aria-hidden', 'true');
    canvas.style.position = 'absolute';
    canvas.style.inset = '0';
    canvas.style.width = '100%';
    canvas.style.height = '100%';
    canvas.style.display = 'block';
    canvas.style.pointerEvents = 'none';
    var host = target || document.body;
    if (getComputedStyle(host).position === 'static') host.style.position = 'relative';
    host.insertBefore(canvas, host.firstChild);

    var ctx = canvas.getContext('2d');
    var COL_WIDTH = spacing * Math.sqrt(3) / 2;

    function draw(){
      var dpr = window.devicePixelRatio || 1;
      var rect = host.getBoundingClientRect();
      var W = Math.max(1, Math.floor(rect.width));
      var H = Math.max(1, Math.floor(rect.height));
      canvas.width = W * dpr;
      canvas.height = H * dpr;
      canvas.style.width = W + 'px';
      canvas.style.height = H + 'px';
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0,0,W,H);

      var cols = Math.ceil(W / COL_WIDTH) + 4;
      var rows = Math.ceil(H / spacing) + 4;
      var originX = W/2 - (cols/2) * COL_WIDTH;
      var originY = H/2 - (rows/2) * spacing;

      var pts = [];
      for (var r = 0; r <= rows; r++){
        pts[r] = [];
        for (var c = 0; c <= cols; c++){
          var yOff = (c % 2 !== 0) ? spacing/2 : 0;
          pts[r][c] = { x: originX + c*COL_WIDTH, y: originY + r*spacing + yOff };
        }
      }
      ctx.strokeStyle = lineColor;
      ctx.lineWidth = lineWidth;
      ctx.lineCap = 'round';
      for (var r2 = 0; r2 <= rows; r2++){
        for (var c2 = 0; c2 <= cols; c2++){
          var p = pts[r2][c2];
          var odd = c2 % 2 !== 0;
          if (r2 < rows){
            ctx.beginPath(); ctx.moveTo(p.x,p.y);
            ctx.lineTo(pts[r2+1][c2].x, pts[r2+1][c2].y); ctx.stroke();
          }
          if (c2 < cols){
            var urR = odd ? r2 : r2-1;
            if (urR >= 0 && urR <= rows){
              ctx.beginPath(); ctx.moveTo(p.x,p.y);
              ctx.lineTo(pts[urR][c2+1].x, pts[urR][c2+1].y); ctx.stroke();
            }
            var lrR = odd ? r2+1 : r2;
            if (lrR >= 0 && lrR <= rows){
              ctx.beginPath(); ctx.moveTo(p.x,p.y);
              ctx.lineTo(pts[lrR][c2+1].x, pts[lrR][c2+1].y); ctx.stroke();
            }
          }
        }
      }
      ctx.fillStyle = dotColor;
      for (var r3 = 0; r3 <= rows; r3++){
        for (var c3 = 0; c3 <= cols; c3++){
          var pp = pts[r3][c3];
          ctx.beginPath();
          ctx.arc(pp.x, pp.y, dotRadius, 0, Math.PI*2);
          ctx.fill();
        }
      }
    }

    var ro = new ResizeObserver(draw);
    ro.observe(host);
    window.addEventListener('resize', draw);
    draw();
    return { redraw: draw, canvas: canvas };
  }

  window.SubstrateLattice = { install: install };
})();
