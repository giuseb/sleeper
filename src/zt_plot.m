function p = zt_plot(data, errs, binhours)
   % ZT_PLOT  line chart with useful defaults for circadian data
   %
   % p = ZT_PLOT(data, errs, binhours)
   
   basex = binhours/2:binhours:24-binhours/2;
   x = staggerx(basex, size(data,2), .5);
   p = plot(x, data, '.-');
   hold on
   errorbar(x, data, errs, 'k.', 'linewidth', 2, 'capsize', 0);
   set(p, 'linewidth', 2, 'markersize', 50);
   yl = get(gca, 'ylim');
   fill([12 24 24 12], [yl(1) yl(1) yl(2) yl(2)], [.9 .9 .9]);
   set(gca, ...
      'xlim', [0 24], ...
      'xtick', 0:binhours:24, ...
      'tickdir', 'out', ...
      'fontsize', 24, ...
      'linewidth', 1, ...
      'children', flipud(get(gca, 'children')))
   
   lx = repmat(binhours:binhours:24-binhours, 2, 1);
   ly = repmat(yl', 1, 24/binhours-1);
   line(lx, ly, 'color',[.5 .5 .5])
   hold off
end