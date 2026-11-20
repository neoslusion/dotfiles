import type { Register } from 'claude-code';
import { renderWorkers, startWorkersPolling } from './workers';

export const register: Register = on => {
  on('session.start', ($, e, next) => {
    startWorkersPolling($);
    return next(e);
  });

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e);
    const workers = await renderWorkers($, e);
    if (!workers) return next(e);
    const { Box } = $.ui.resolve(e);
    return (<Box flexDirection="column">{workers}{await next(e)}</Box>);
  });
};
