import logging
import logging.handlers
import sys


def log_exception_handler(type, value, tb):
    logger = logging.getLogger('tom')
    logger.exception("Uncaught exception: {0}".format(str(value)))



def setup_logging(module_loglevel, module_logfilesize, module_logfilecount, logfile):
    module_logger = logging.getLogger('server-scanner')
    module_logger.setLevel(module_loglevel)

    handler = logging.handlers.RotatingFileHandler(
                          logfile,
                          maxBytes=module_logfilesize*1024,
                          backupCount=module_logfilecount-1)

    formatter = logging.Formatter(
        ' '.join(['[%(asctime)s]',
                  '%(levelname)s',
                  '[%(process)d - %(threadName)s]',
                  '%(message)s'])
        )
    handler.setFormatter(formatter)
    module_logger.addHandler(handler)
    sys.excepthook = log_exception_handler
    return
